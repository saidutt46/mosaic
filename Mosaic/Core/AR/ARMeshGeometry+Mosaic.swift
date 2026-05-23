//
//  ARMeshGeometry+Mosaic.swift
//  Mosaic
//
//  Buffer-aware accessors for ARMeshGeometry — ported from Apple's
//  "Visualizing and Interacting with a Reconstructed Scene" sample.
//
//  ARKit hands us geometry as raw Metal buffers (vertices, faces,
//  classification) with `offset` and `stride`. These helpers do the
//  pointer arithmetic correctly so callers don't have to. They are
//  used today by ClassificationStats and will be reused verbatim by
//  the Metal renderer in Phase 6 (no copying — same buffers).
//

import Foundation
import ARKit
import Metal
import simd

// MARK: - simd_float4x4

extension simd_float4x4 {
    /// Translation column extracted as a 3-vector.
    var position: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

// MARK: - ARMeshClassification

extension ARMeshClassification {
    /// Short lowercase label used in logs and UI swatches.
    var label: String {
        switch self {
        case .ceiling: "ceiling"
        case .door:    "door"
        case .floor:   "floor"
        case .seat:    "seat"
        case .table:   "table"
        case .wall:    "wall"
        case .window:  "window"
        case .none:    "none"
        @unknown default: "?"
        }
    }

    /// All 8 cases ARKit currently emits, in raw-value order.
    static let allKnown: [ARMeshClassification] = [
        .none, .wall, .floor, .ceiling, .table, .seat, .window, .door,
    ]
}

// MARK: - ARMeshGeometry

extension ARMeshGeometry {

    /// Vertex position at the given vertex index, in anchor-local space.
    func vertex(at index: UInt32) -> SIMD3<Float> {
        assert(vertices.format == .float3, "Expected float3 vertex format")
        let ptr = vertices.buffer.contents()
            .advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let triple = ptr.assumingMemoryBound(to: (Float, Float, Float).self).pointee
        return SIMD3<Float>(triple.0, triple.1, triple.2)
    }

    /// Classification for the face at the given index.
    /// Returns `.none` if the anchor has no classification buffer
    /// (e.g. running without `.meshWithClassification`).
    func classification(faceIndex: Int) -> ARMeshClassification {
        guard let cls = classification else { return .none }
        assert(cls.format == .uchar, "Expected uchar classification format")
        let ptr = cls.buffer.contents()
            .advanced(by: cls.offset + (cls.stride * faceIndex))
        let raw = Int(ptr.assumingMemoryBound(to: CUnsignedChar.self).pointee)
        return ARMeshClassification(rawValue: raw) ?? .none
    }

    /// Triangle vertex indices for the face at the given index.
    func triangleIndices(faceIndex: Int) -> (UInt32, UInt32, UInt32) {
        assert(faces.bytesPerIndex == MemoryLayout<UInt32>.size, "Expected UInt32 indices")
        assert(faces.indexCountPerPrimitive == 3, "Expected triangle faces")
        let byteOffset = faceIndex * 3 * MemoryLayout<UInt32>.size
        let buf = faces.buffer.contents()
            .advanced(by: byteOffset)
            .assumingMemoryBound(to: UInt32.self)
        return (buf[0], buf[1], buf[2])
    }

    /// Centroid of the face at the given index, in anchor-local space.
    func centroid(faceIndex: Int) -> SIMD3<Float> {
        let (a, b, c) = triangleIndices(faceIndex: faceIndex)
        return (vertex(at: a) + vertex(at: b) + vertex(at: c)) / 3
    }
}
