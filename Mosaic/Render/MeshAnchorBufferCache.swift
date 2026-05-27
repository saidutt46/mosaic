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
///
/// `@unchecked Sendable`: every buffer is owned, `.storageModeShared`,
/// and immutable once built — the cache replaces entries wholesale,
/// never mutates buffer contents. A `snapshot` array therefore holds
/// strong refs to frozen buffers, safe to read from a background task
/// (e.g. USDZ export) concurrently with the renderer's GPU reads.
struct MeshAnchorBuffers: @unchecked Sendable {
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

    /// `faceCount` `Float` per-face triangle areas (m²), for the
    /// density visualization mode. World-space == local-space here
    /// since ARKit mesh-anchor transforms are rigid.
    let areaBuffer: MTLBuffer?
}

@MainActor
final class MeshAnchorBufferCache {

    private let device: MTLDevice
    private var entries: [UUID: MeshAnchorBuffers] = [:]

    // MARK: - Density histogram (adaptive ramp bounds, F.1.2)
    //
    // The density ramp normalises against the scene's *actual* face-area
    // distribution, not a fixed window — so it reads sensibly in any room.
    // We maintain a coarse log2(area) histogram incrementally as anchors
    // come and go (each face is binned once at build time; a replaced or
    // removed anchor subtracts its old contribution). Ramp bounds are the
    // p5 / p95 percentiles, which clip the degenerate-sliver and giant-face
    // tails that would otherwise skew the range.
    private static let logAreaMin: Float = -16
    private static let logAreaMax: Float = 0
    private static let binCount = 64
    private static let binWidth = (logAreaMax - logAreaMin) / Float(binCount)
    private static let lowPercentile: Float = 0.05
    private static let highPercentile: Float = 0.95

    /// Fallback bounds when no mesh has accumulated yet — the original
    /// hand-tuned window (≈0.00024 m² dense … ≈0.0078 m² sparse).
    private static let fallbackLogBounds: (min: Float, max: Float) = (-12, -7)

    private var logAreaHistogram = [Int](repeating: 0, count: binCount)
    private var histogramTotal = 0

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

    /// Adaptive log2(area) ramp bounds for the density visualization —
    /// the p5 / p95 percentiles of the live scene's face areas. Cheap
    /// (scans the 64-bin histogram); read once per frame by the overlay
    /// pass. Falls back to the fixed window before any mesh accumulates.
    var densityLogBounds: (min: Float, max: Float) {
        guard histogramTotal > 0 else { return Self.fallbackLogBounds }

        let lowTarget = Int(Float(histogramTotal) * Self.lowPercentile)
        let highTarget = Int(Float(histogramTotal) * Self.highPercentile)
        var cumulative = 0
        var loBin = 0
        var hiBin = Self.binCount - 1
        var foundLo = false
        for b in 0..<Self.binCount {
            cumulative += logAreaHistogram[b]
            if !foundLo && cumulative >= lowTarget { loBin = b; foundLo = true }
            if cumulative >= highTarget { hiBin = b; break }
        }

        let lo = Self.logAreaMin + (Float(loBin) + 0.5) * Self.binWidth
        var hi = Self.logAreaMin + (Float(hiBin) + 0.5) * Self.binWidth
        // Guard against a collapsed range (a near-uniform scene) so the
        // ramp never divides by ~zero and flattens to one colour.
        if hi - lo < 1.0 { hi = lo + 1.0 }
        return (lo, hi)
    }

    // MARK: - Lifecycle

    func update(from anchor: ARMeshAnchor) {
        guard let buffers = makeBuffers(for: anchor) else {
            Log.metal.warning("mesh cache: failed to build buffers for \(anchor.identifier.uuidString.prefix(8), privacy: .public)")
            return
        }
        let previous = entries[anchor.identifier]
        if let previous { accumulateHistogram(for: previous, sign: -1) }
        entries[anchor.identifier] = buffers
        accumulateHistogram(for: buffers, sign: 1)
        if previous == nil {
            Log.metal.debug("mesh cache: +anchor \(anchor.identifier.uuidString.prefix(8), privacy: .public) verts=\(buffers.vertexCount) faces=\(buffers.faceCount)")
        }
    }

    func remove(_ anchor: ARMeshAnchor) {
        guard let removed = entries.removeValue(forKey: anchor.identifier) else { return }
        accumulateHistogram(for: removed, sign: -1)
        Log.metal.debug("mesh cache: -anchor \(anchor.identifier.uuidString.prefix(8), privacy: .public)")
    }

    func reset() {
        let count = entries.count
        entries.removeAll()
        logAreaHistogram = [Int](repeating: 0, count: Self.binCount)
        histogramTotal = 0
        if count > 0 {
            Log.metal.info("mesh cache: reset (\(count) anchors dropped)")
        }
    }

    /// Add (`sign` +1) or subtract (`sign` -1) an anchor's per-face areas
    /// from the log2(area) histogram. Called when an anchor is built,
    /// replaced, or removed so percentiles track the live scene.
    private func accumulateHistogram(for buffers: MeshAnchorBuffers, sign: Int) {
        guard let areaBuffer = buffers.areaBuffer else { return }
        let areas = areaBuffer.contents().assumingMemoryBound(to: Float.self)
        for f in 0..<buffers.faceCount {
            let logArea = log2(max(areas[f], 1e-9))
            let raw = (logArea - Self.logAreaMin) / Self.binWidth
            let bin = min(max(Int(raw), 0), Self.binCount - 1)
            logAreaHistogram[bin] += sign
            histogramTotal += sign
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

        // float3 has 12 bytes of actual data per element. Swift's
        // SIMD3<Float> is 16-byte aligned (4 trailing padding bytes)
        // to match Metal's float3, but ARKit may deliver vertices /
        // normals with either 12- or 16-byte stride depending on the
        // device. Copy exactly 12 bytes per source slot into 16-byte
        // dest slots — trailing padding stays uninitialised, but the
        // shader's float3 only reads the first 3 floats.
        let float3Payload = MemoryLayout<(Float, Float, Float)>.size  // 12
        let float3SlotSize = MemoryLayout<SIMD3<Float>>.size           // 16

        guard let vertexBuffer = copyStridedSource(
            buffer: geom.vertices.buffer,
            offset: geom.vertices.offset,
            stride: geom.vertices.stride,
            payloadBytes: float3Payload,
            elementSize: float3SlotSize,
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
                payloadBytes: float3Payload,
                elementSize: float3SlotSize,
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
                payloadBytes: MemoryLayout<UInt8>.size,
                elementSize: MemoryLayout<UInt8>.size,
                elementCount: faceCount,
                label: "Mosaic.MeshClassification"
            )
        }

        // Per-face triangle area (m²) for the density visualization.
        var areaBuffer: MTLBuffer?
        if let buffer = device.makeBuffer(length: faceCount * MemoryLayout<Float>.size,
                                           options: .storageModeShared) {
            buffer.label = "Mosaic.MeshFaceAreas"
            let verts = vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self)
            let idx = indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
            let areas = buffer.contents().assumingMemoryBound(to: Float.self)
            for f in 0..<faceCount {
                let p0 = verts[Int(idx[f * 3])]
                let p1 = verts[Int(idx[f * 3 + 1])]
                let p2 = verts[Int(idx[f * 3 + 2])]
                areas[f] = 0.5 * simd_length(simd_cross(p1 - p0, p2 - p0))
            }
            areaBuffer = buffer
        }

        return MeshAnchorBuffers(
            identifier: anchor.identifier,
            transform: anchor.transform,
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            normalBuffer: normalBuffer,
            indexBuffer: indexBuffer,
            faceCount: faceCount,
            classificationBuffer: classificationBuffer,
            areaBuffer: areaBuffer
        )
    }

    /// Copy a (possibly strided) source range into a destination
    /// MTLBuffer. `payloadBytes` is the actual bytes of data per
    /// element (≤ both stride and elementSize); `elementSize` is
    /// the dest slot size. They differ when the dest needs
    /// alignment padding (e.g. SIMD3<Float> data = 12 bytes, slot
    /// = 16 bytes). The fast path runs only when everything aligns;
    /// otherwise we walk element-by-element and copy exactly
    /// payloadBytes per slot — never reading past the source even
    /// when source stride < element size.
    private func copyStridedSource(
        buffer source: MTLBuffer,
        offset sourceOffset: Int,
        stride sourceStride: Int,
        payloadBytes: Int,
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

        if sourceStride == elementSize && payloadBytes == elementSize {
            memcpy(dstBase, srcBase, destByteSize)
        } else {
            for i in 0..<elementCount {
                memcpy(dstBase.advanced(by: i * elementSize),
                       srcBase.advanced(by: i * sourceStride),
                       payloadBytes)
            }
        }

        return dest
    }
}
