//
//  CoveragePLYExporter.swift
//  Mosaic
//
//  Writes the scan-coverage voxel grid (F.2.3) as a colored point cloud
//  (.ply). One point per occupied voxel, positioned at the voxel centre
//  in world metres, coloured by accumulated quality through the same
//  red→yellow→green ramp the live mesh overlay uses.
//
//  Binary little-endian PLY, dependency-free. Mirrors PLYExporter's
//  format so anything that reads the existing pointcloud.ply reads this
//  too (just a different artifact in the same scan folder).
//

import Foundation
import simd
import os

enum CoveragePLYExporter {

    enum ExportError: Error { case emptyCloud }

    static func write(snapshot: CoverageSnapshot, to url: URL) throws {
        guard !snapshot.isEmpty else { throw ExportError.emptyCloud }

        var body = Data()
        body.reserveCapacity(snapshot.count * 15)  // 3·float + 3·uchar

        for p in snapshot.points {
            appendFloatLE(&body, p.x)
            appendFloatLE(&body, p.y)
            appendFloatLE(&body, p.z)
            let (r, g, b) = rampRGB(p.w)
            body.append(r)
            body.append(g)
            body.append(b)
        }

        let header = """
        ply
        format binary_little_endian 1.0
        comment Mosaic scan-coverage point cloud
        comment voxel_size_m \(snapshot.voxelSize)
        element vertex \(snapshot.count)
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

        Log.app.info("coverage.ply: \(snapshot.count) voxels → \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Helpers

    /// Quality → RGB through the same red(0) → yellow(0.5) → green(1)
    /// ramp the meshFragment uses for the coverage mode.
    private static func rampRGB(_ quality: Float) -> (UInt8, UInt8, UInt8) {
        let t = max(0, min(1, quality))
        let low  = SIMD3<Float>(1.00, 0.23, 0.19)
        let mid  = SIMD3<Float>(1.00, 0.80, 0.00)
        let high = SIMD3<Float>(0.20, 0.78, 0.35)
        let c: SIMD3<Float> = t < 0.5
            ? simd_mix(low, mid, SIMD3<Float>(repeating: t * 2))
            : simd_mix(mid, high, SIMD3<Float>(repeating: (t - 0.5) * 2))
        return (byte(c.x), byte(c.y), byte(c.z))
    }

    private static func appendFloatLE(_ data: inout Data, _ value: Float) {
        var le = value.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func byte(_ unit: Float) -> UInt8 {
        UInt8(max(0, min(1, unit)) * 255)
    }
}
