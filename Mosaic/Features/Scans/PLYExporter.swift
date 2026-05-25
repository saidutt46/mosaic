//
//  PLYExporter.swift
//  Mosaic
//
//  Writes a semantic point cloud (.ply) from a mesh-cache snapshot.
//  The points are the mesh vertices baked into world space, each
//  coloured by its ARMeshClassification (same palette as the render
//  overlay) — so the cloud carries the semantic colouring, not just
//  geometry. Binary little-endian PLY, dependency-free.
//
//  Classification is per-face in ARKit; we fold it down to per-vertex
//  by taking the first face that references each vertex (adjacent
//  faces almost always share a class, so boundaries are the only
//  ambiguity and the choice there is arbitrary either way).
//

import Foundation
import Metal
import simd
import os

enum PLYExporter {

    enum ExportError: Error { case emptyCloud }

    static func write(snapshot: [MeshAnchorBuffers],
                      palette: [SIMD4<Float>],
                      to url: URL) throws {

        var body = Data()
        var count = 0

        for anchor in snapshot {
            let verts = anchor.vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self)
            let idx = anchor.indexBuffer.contents().assumingMemoryBound(to: UInt32.self)

            // Per-vertex class via first referencing face.
            var vertexClass = [UInt8](repeating: 0, count: anchor.vertexCount)
            if let cls = anchor.classificationBuffer?.contents().assumingMemoryBound(to: UInt8.self) {
                var assigned = [Bool](repeating: false, count: anchor.vertexCount)
                for face in 0..<anchor.faceCount {
                    let c = cls[face]
                    for k in 0..<3 {
                        let vi = Int(idx[face * 3 + k])
                        if !assigned[vi] { vertexClass[vi] = c; assigned[vi] = true }
                    }
                }
            }

            let model = anchor.transform
            for v in 0..<anchor.vertexCount {
                let lp = verts[v]
                let wp = model * SIMD4<Float>(lp.x, lp.y, lp.z, 1)
                appendFloatLE(&body, wp.x)
                appendFloatLE(&body, wp.y)
                appendFloatLE(&body, wp.z)

                let c = Int(min(vertexClass[v], UInt8(palette.count - 1)))
                let color = palette[c]
                body.append(byte(color.x))
                body.append(byte(color.y))
                body.append(byte(color.z))
                count += 1
            }
        }

        guard count > 0 else { throw ExportError.emptyCloud }

        let header = """
        ply
        format binary_little_endian 1.0
        comment Mosaic semantic point cloud
        element vertex \(count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """

        var out = Data(header.utf8)
        out.append(body)
        try out.write(to: url)

        Log.app.info("ply export: \(count) points → \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Byte helpers

    private static func appendFloatLE(_ data: inout Data, _ value: Float) {
        var le = value.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func byte(_ unit: Float) -> UInt8 {
        UInt8(max(0, min(1, unit)) * 255)
    }
}
