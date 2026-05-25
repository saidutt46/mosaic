//
//  USDZExporter.swift
//  Mosaic
//
//  Converts a MeshAnchorBufferCache snapshot into a USDZ file for
//  external sharing (AirDrop, Files, QuickLook AR preview) via Apple
//  ModelIO. No third-party deps.
//
//  Organisation is per-classification, not per-anchor (a deliberate
//  deviation from the E-mesh-persistence-plan, which specified per-
//  anchor MDLMesh + per-class submesh). ARKit mesh anchors are
//  arbitrary spatial tiles, not objects — preserving them in a shared
//  artifact adds node count without meaning. Instead every anchor's
//  faces are baked into world space and grouped by ARMeshClassification
//  into one MDLMesh each (named "wall", "floor", …) with a shared
//  MDLMaterial per class, so the recipient gets up to 8 cleanly named,
//  individually colour-/visibility-controllable meshes. Full anchor
//  structure (UUIDs, transforms) is instead preserved losslessly in
//  our own mesh.json for the in-app viewer (E.2.1).
//
//  Buffers are Metal/GPU-backed (MTKMeshBufferAllocator) so the same
//  MDLMesh can round-trip into an MTKMesh for that viewer.
//
//  Lives in Features/Scans/ (not Render/) because it depends on
//  high-level Apple frameworks, not the Metal draw path.
//
//  Limitation: meshes export single-sided. ARKit's mesh has no
//  consistent winding, so a viewer with backface culling may drop
//  some triangles; QuickLook tolerates this in practice.
//

import Foundation
import ModelIO
import MetalKit
import ARKit
import simd
import CoreGraphics
import os

enum USDZExporter {

    enum ExportError: Error {
        case emptyMesh                 // no anchors had geometry to write
        case unsupportedExportFormat   // ModelIO can't write usdz here
    }

    /// Metres → centimetres. USD's default `metersPerUnit` is 0.01 and
    /// ModelIO doesn't emit one, so we author in cm to land at real scale.
    private static let unitScale: Float = 100

    /// Serialise `snapshot` to a USDZ at `url`. Synchronous and CPU-
    /// bound (0.5–3s for a room) — the caller must run it off the main
    /// actor. `palette` is indexed by `ARMeshClassification` raw value;
    /// `density` mirrors the on-screen density knob (1 = every face).
    static func write(snapshot: [MeshAnchorBuffers],
                      palette: [SIMD4<Float>],
                      density: MeshDensity = .full,
                      to url: URL) throws {

        // ModelIO can write binary USD (.usdc) on iOS but NOT the zipped
        // .usdz wrapper (verified at runtime — iOS exports usdc/usda/usd/
        // obj/ply/stl/abc only). So we export .usdc, then package it into
        // a .usdz ourselves (USDZ = an uncompressed, 64-byte-aligned zip).
        guard MDLAsset.canExportFileExtension("usdc") else {
            Log.app.error("usdz export: ModelIO cannot export usdc on this OS")
            throw ExportError.unsupportedExportFormat
        }

        let classCount = ARMeshClassification.allKnown.count   // 8
        let stride = Int(density.rawValue)

        // Per-class world-space accumulators.
        var positions = Array(repeating: [SIMD3<Float>](), count: classCount)
        var normals   = Array(repeating: [SIMD3<Float>](), count: classCount)
        var indices   = Array(repeating: [UInt32](),       count: classCount)

        for anchor in snapshot {
            guard let normalBuffer = anchor.normalBuffer,
                  let classBuffer = anchor.classificationBuffer else { continue }

            let verts = anchor.vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self)
            let norms = normalBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self)
            let idx = anchor.indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
            let cls = classBuffer.contents().assumingMemoryBound(to: UInt8.self)

            let model = anchor.transform
            let normalMatrix = simd_float3x3(
                SIMD3(model.columns.0.x, model.columns.0.y, model.columns.0.z),
                SIMD3(model.columns.1.x, model.columns.1.y, model.columns.1.z),
                SIMD3(model.columns.2.x, model.columns.2.y, model.columns.2.z)
            )

            // Dedup within this anchor + class: a local vertex index
            // reused by two same-class faces emits one world vertex.
            var remap = Array(repeating: [UInt32: UInt32](), count: classCount)

            for face in 0..<anchor.faceCount {
                if stride > 1 && face % stride != 0 { continue }   // matches shader density discard

                let c = Int(min(cls[face], UInt8(classCount - 1)))

                for k in 0..<3 {
                    let local = idx[face * 3 + k]
                    let global: UInt32
                    if let existing = remap[c][local] {
                        global = existing
                    } else {
                        let lp = verts[Int(local)]
                        let worldPos = model * SIMD4<Float>(lp.x, lp.y, lp.z, 1)
                        let worldNrm = simd_normalize(normalMatrix * norms[Int(local)])
                        global = UInt32(positions[c].count)
                        // ARKit gives metres, but ModelIO writes no USD
                        // `metersPerUnit`, so consumers fall back to the USD
                        // default of 0.01 (centimetres). Author in cm (×100)
                        // so a 4 m room reads back as 4 m, not 4 cm (the
                        // "matchbox in AR" bug).
                        positions[c].append(SIMD3(worldPos.x, worldPos.y, worldPos.z) * Self.unitScale)
                        normals[c].append(worldNrm)
                        remap[c][local] = global
                    }
                    indices[c].append(global)
                }
            }
        }

        // Metal/GPU-backed allocator: the canonical ModelIO+Metal path
        // on Apple silicon, and it lets these MDLMeshes round-trip into
        // an MTKMesh for the in-app viewer (E.2.1) without a re-upload.
        let allocator = MTKMeshBufferAllocator(device: MetalContext.shared.device)
        let asset = MDLAsset(bufferAllocator: allocator)
        let descriptor = interleavedDescriptor()

        for c in 0..<classCount where !indices[c].isEmpty {
            let mesh = makeMesh(
                positions: positions[c],
                normals: normals[c],
                indices: indices[c],
                material: material(forClass: c, palette: palette),
                descriptor: descriptor,
                allocator: allocator
            )
            mesh.name = ARMeshClassification.allKnown[c].label
            asset.add(mesh)
        }

        guard asset.count > 0 else { throw ExportError.emptyMesh }

        // ModelIO writes the USD layer; we wrap it as USDZ. The inner
        // file keeps the .usdc name matching the scan's artifact stem.
        let innerName = url.deletingPathExtension().appendingPathExtension("usdc").lastPathComponent
        let usdcURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("usdc")
        defer { try? FileManager.default.removeItem(at: usdcURL) }

        try asset.export(to: usdcURL)
        let usdcData = try Data(contentsOf: usdcURL)
        try USDZArchive.write(usdData: usdcData, innerName: innerName, to: url)

        Log.app.info("usdz export: \(asset.count) class mesh(es), \(usdcData.count) usdc bytes → \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Mesh construction

    /// Single interleaved buffer: position(float3) + normal(float3),
    /// 24-byte stride.
    private static func interleavedDescriptor() -> MDLVertexDescriptor {
        let vd = MDLVertexDescriptor()
        vd.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vd.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
        vd.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 6)
        return vd
    }

    private static func makeMesh(positions: [SIMD3<Float>],
                                 normals: [SIMD3<Float>],
                                 indices: [UInt32],
                                 material: MDLMaterial,
                                 descriptor: MDLVertexDescriptor,
                                 allocator: MDLMeshBufferAllocator) -> MDLMesh {
        var interleaved = [Float]()
        interleaved.reserveCapacity(positions.count * 6)
        for i in 0..<positions.count {
            let p = positions[i], n = normals[i]
            interleaved.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z])
        }

        let vertexData = interleaved.withUnsafeBytes { Data($0) }
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        let indexData = indices.withUnsafeBytes { Data($0) }
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: material
        )

        return MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: positions.count,
            descriptor: descriptor,
            submeshes: [submesh]
        )
    }

    // MARK: - Materials

    private static func material(forClass c: Int,
                                 palette: [SIMD4<Float>]) -> MDLMaterial {
        let color = c < palette.count ? palette[c] : SIMD4<Float>(0.5, 0.5, 0.5, 1)

        // baseColor MUST be a CGColor: that makes ModelIO emit a USD
        // *color* type (color4f) for diffuseColor. A plain float3 is not
        // a color-role type, so QuickLook / RealityKit ignore it and the
        // model renders default gray.
        let scatter = MDLPhysicallyPlausibleScatteringFunction()
        scatter.baseColor.color = CGColor(srgbRed: CGFloat(color.x),
                                          green: CGFloat(color.y),
                                          blue: CGFloat(color.z),
                                          alpha: CGFloat(color.w))
        scatter.metallic.floatValue = 0
        scatter.roughness.floatValue = 0.85

        return MDLMaterial(name: ARMeshClassification.allKnown[c].label,
                           scatteringFunction: scatter)
    }
}
