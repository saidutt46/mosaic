//
//  MeshAnchorBufferCache.swift
//  Mosaic
//
//  Per-ARMeshAnchor cache of GPU buffers. ARKit hands us geometry
//  as strided MTLBuffer-backed sources whose lifetime is tied to
//  the frame; we copy into tightly-packed owned buffers so the
//  renderer can sample them freely across draw calls without
//  worrying about ARKit recycling memory.
//
//  Updated incrementally by ARSessionManager from the ARSession
//  delegate (didAdd / didUpdate / didRemove). The renderer in B.2
//  will read `snapshot` once per frame and issue one draw call per
//  cached entry.
//
//  This file is pure data plumbing — no rendering, no shaders.
//

import Foundation
import Metal
import ARKit
import simd
import os

/// A single ARMeshAnchor's geometry copied into tightly-packed
/// MTLBuffers, plus the anchor's world transform. Indices and
/// classifications are present whenever ARKit provides them
/// (classification requires `.meshWithClassification` config).
struct MeshAnchorBuffers {
    let identifier: UUID
    var transform: simd_float4x4

    /// `vertexCount` `SIMD3<Float>` positions, anchor-local space.
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    /// `vertexCount` `SIMD3<Float>` normals (matches vertex layout).
    let normalBuffer: MTLBuffer?

    /// `faceCount * 3` `UInt32` triangle vertex indices.
    let indexBuffer: MTLBuffer
    let faceCount: Int

    /// `faceCount` `UInt8` classification values
    /// (raw values of `ARMeshClassification`).
    let classificationBuffer: MTLBuffer?
}

@MainActor
final class MeshAnchorBufferCache {

    private let device: MTLDevice
    private var entries: [UUID: MeshAnchorBuffers] = [:]

    init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Public stats

    var anchorCount: Int { entries.count }

    var totalFaceCount: Int {
        entries.values.reduce(0) { $0 + $1.faceCount }
    }

    var totalVertexCount: Int {
        entries.values.reduce(0) { $0 + $1.vertexCount }
    }

    /// Snapshot for the renderer to iterate. Returns an array of
    /// value-type structs holding strong MTLBuffer references; safe
    /// to retain across the draw call.
    var snapshot: [MeshAnchorBuffers] {
        Array(entries.values)
    }

    // MARK: - Lifecycle

    func update(from anchor: ARMeshAnchor) {
        guard let buffers = makeBuffers(for: anchor) else {
            Log.metal.warning("mesh cache: failed to build buffers for \(anchor.identifier.uuidString.prefix(8), privacy: .public)")
            return
        }
        let isNew = entries[anchor.identifier] == nil
        entries[anchor.identifier] = buffers
        if isNew {
            Log.metal.debug("mesh cache: +anchor \(anchor.identifier.uuidString.prefix(8), privacy: .public) verts=\(buffers.vertexCount) faces=\(buffers.faceCount)")
        }
    }

    func remove(_ anchor: ARMeshAnchor) {
        guard entries.removeValue(forKey: anchor.identifier) != nil else { return }
        Log.metal.debug("mesh cache: -anchor \(anchor.identifier.uuidString.prefix(8), privacy: .public)")
    }

    func reset() {
        let count = entries.count
        entries.removeAll()
        if count > 0 {
            Log.metal.info("mesh cache: reset (\(count) anchors dropped)")
        }
    }

    // MARK: - Buffer construction

    private func makeBuffers(for anchor: ARMeshAnchor) -> MeshAnchorBuffers? {
        let geom = anchor.geometry
        let vertexCount = geom.vertices.count
        let faceCount = geom.faces.count

        guard vertexCount > 0, faceCount > 0 else { return nil }

        // Sanity: we depend on these layouts throughout the renderer.
        assert(geom.vertices.format == .float3, "expected float3 vertices")
        assert(geom.faces.bytesPerIndex == MemoryLayout<UInt32>.size,
               "expected UInt32 indices")
        assert(geom.faces.indexCountPerPrimitive == 3,
               "expected triangle faces")

        // Vertices — tightly packed float3.
        guard let vertexBuffer = copyStridedSource(
            buffer: geom.vertices.buffer,
            offset: geom.vertices.offset,
            stride: geom.vertices.stride,
            elementSize: MemoryLayout<SIMD3<Float>>.size,
            elementCount: vertexCount,
            label: "Mosaic.MeshVertices"
        ) else { return nil }

        // Normals — optional but ARKit provides them on modern iOS.
        var normalBuffer: MTLBuffer?
        let normalCount = geom.normals.count
        if normalCount > 0 {
            assert(normalCount == vertexCount,
                   "normals expected to match vertex count")
            normalBuffer = copyStridedSource(
                buffer: geom.normals.buffer,
                offset: geom.normals.offset,
                stride: geom.normals.stride,
                elementSize: MemoryLayout<SIMD3<Float>>.size,
                elementCount: normalCount,
                label: "Mosaic.MeshNormals"
            )
        }

        // Indices — ARGeometryElement packs them tightly, so a
        // single memcpy of the whole region works.
        let indexCount = faceCount * 3
        let indexByteSize = indexCount * MemoryLayout<UInt32>.size
        guard let indexBuffer = device.makeBuffer(
            length: indexByteSize,
            options: .storageModeShared
        ) else { return nil }
        indexBuffer.label = "Mosaic.MeshIndices"
        memcpy(indexBuffer.contents(),
               geom.faces.buffer.contents(),
               indexByteSize)

        // Classification — only present under .meshWithClassification.
        var classificationBuffer: MTLBuffer?
        if let cls = geom.classification {
            assert(cls.format == .uchar,
                   "expected uchar classification format")
            classificationBuffer = copyStridedSource(
                buffer: cls.buffer,
                offset: cls.offset,
                stride: cls.stride,
                elementSize: MemoryLayout<UInt8>.size,
                elementCount: faceCount,
                label: "Mosaic.MeshClassification"
            )
        }

        return MeshAnchorBuffers(
            identifier: anchor.identifier,
            transform: anchor.transform,
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            normalBuffer: normalBuffer,
            indexBuffer: indexBuffer,
            faceCount: faceCount,
            classificationBuffer: classificationBuffer
        )
    }

    /// Copy a (possibly strided) source range into a tightly-packed
    /// destination MTLBuffer. If `stride == elementSize` (already
    /// packed) a single memcpy is sufficient; otherwise we walk
    /// element-by-element.
    private func copyStridedSource(
        buffer source: MTLBuffer,
        offset sourceOffset: Int,
        stride sourceStride: Int,
        elementSize: Int,
        elementCount: Int,
        label: String
    ) -> MTLBuffer? {
        let destByteSize = elementSize * elementCount
        guard let dest = device.makeBuffer(
            length: destByteSize,
            options: .storageModeShared
        ) else { return nil }
        dest.label = label

        let srcBase = source.contents().advanced(by: sourceOffset)
        let dstBase = dest.contents()

        if sourceStride == elementSize {
            memcpy(dstBase, srcBase, destByteSize)
        } else {
            for i in 0..<elementCount {
                memcpy(dstBase.advanced(by: i * elementSize),
                       srcBase.advanced(by: i * sourceStride),
                       elementSize)
            }
        }

        return dest
    }
}
