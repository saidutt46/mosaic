//
//  CoverageGrid.swift
//  Mosaic
//
//  F.2.1b — world-space coverage accumulation. ARKit replaces mesh
//  geometry (and re-indexes faces) on every update, so scan-coverage
//  history can't live on a face. It lives here instead, keyed by
//  quantized world position: a sparse voxel grid holding the BEST
//  observation quality seen per cell ("paint what you've captured").
//
//  Per frame we unproject sceneDepth into world points and splat
//  `quality = confidence × proximity` into the grid via max(). This is
//  a TSDF-lite (quality-occupancy only, no signed distance — ARKit
//  already gives us the mesh). Renders as persistent points via
//  DepthPointCloudPass; later feeds the .coverage mesh mode (F.2.2) and
//  a coverage.ply export.
//
//  Touched only from the render thread (Renderer.draw, main) — plain
//  data, no shaders.
//

import Foundation
import ARKit
import simd
import CoreVideo
import os

/// Immutable, off-thread-safe copy of the grid for export. xyz = world
/// voxel-centre (metres); w = accumulated quality in [0, 1].
struct CoverageSnapshot: Sendable {
    let voxelSize: Float
    let points: [SIMD4<Float>]
    var isEmpty: Bool { points.isEmpty }
    var count: Int { points.count }
}

final class CoverageGrid {

    /// All tunable — 5 cm reads well on device; revisit if face-centroid
    /// lookups miss (raise to 8–10 cm) or accumulation costs too much
    /// (raise the stride / Nth-frame).
    struct Tuning {
        var voxelSize: Float = 0.05        // 5 cm cells
        var maxRange: Float = 4.0          // proximity falloff (m)
        var subsampleStride: Int = 2       // over the 256×192 depth map
        var ingestEveryNthFrame: Int = 3   // ~20 Hz accumulation at 60 fps
    }

    var tuning = Tuning()

    /// voxel key → best observed quality in [0, 1].
    private var cells: [Int64: Float] = [:]
    private var frameCounter = 0

    /// Bumps whenever the grid's contents change, so the render pass
    /// can skip rebuilding its point buffer on no-op frames.
    private(set) var version = 0

    var occupiedCount: Int { cells.count }

    func reset() {
        guard !cells.isEmpty else { return }
        cells.removeAll(keepingCapacity: true)
        version &+= 1
    }

    // MARK: - Accumulation

    /// Unproject + splat one frame (throttled by `ingestEveryNthFrame`).
    @discardableResult
    func ingest(depthMap: CVPixelBuffer,
                confidenceMap: CVPixelBuffer,
                camera: ARCamera) -> Bool {
        frameCounter &+= 1
        if tuning.ingestEveryNthFrame > 1,
           frameCounter % tuning.ingestEveryNthFrame != 0 { return false }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let confBase = CVPixelBufferGetBaseAddress(confidenceMap) else { return false }
        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let confRowBytes = CVPixelBufferGetBytesPerRow(confidenceMap)

        // Intrinsics scaled from the full-res captured image down to the
        // depth-map resolution (aspect matches → uniform scale).
        let intrinsics = camera.intrinsics
        let s = Float(width) / Float(camera.imageResolution.width)
        let fx = intrinsics[0][0] * s
        let fy = intrinsics[1][1] * s
        let cx = intrinsics[2][0] * s
        let cy = intrinsics[2][1] * s
        let transform = camera.transform
        let invVoxel = 1.0 / tuning.voxelSize
        let invRange = 1.0 / tuning.maxRange
        let step = max(1, tuning.subsampleStride)

        var changed = false
        for row in stride(from: 0, to: height, by: step) {
            let depthRow = depthBase.advanced(by: row * depthRowBytes)
                .assumingMemoryBound(to: Float32.self)
            let confRow = confBase.advanced(by: row * confRowBytes)
                .assumingMemoryBound(to: UInt8.self)
            for col in stride(from: 0, to: width, by: step) {
                let d = depthRow[col]
                guard d > 0, d.isFinite else { continue }
                // CV camera frame → ARKit camera frame (flip Y/Z).
                let x = (Float(col) - cx) / fx * d
                let y = -(Float(row) - cy) / fy * d
                let world = transform * SIMD4<Float>(x, y, -d, 1.0)

                let confW = (Float(confRow[col]) + 1) / 3.0          // .33 / .67 / 1
                let proxW = simd_clamp(1 - d * invRange, 0, 1)        // closer → better
                let quality = confW * proxW

                let key = Self.voxelKey(world.x * invVoxel,
                                        world.y * invVoxel,
                                        world.z * invVoxel)
                if let existing = cells[key] {
                    if quality > existing { cells[key] = quality; changed = true }
                } else {
                    cells[key] = quality
                    changed = true
                }
            }
        }
        if changed { version &+= 1 }
        return changed
    }

    // MARK: - Readout

    /// Best accumulated quality at a world point (0 if its voxel has
    /// never been observed). Used to colour mesh faces by coverage.
    func quality(atWorld point: SIMD3<Float>) -> Float {
        let inv = 1.0 / tuning.voxelSize
        let key = Self.voxelKey(point.x * inv, point.y * inv, point.z * inv)
        return cells[key] ?? 0
    }

    /// Coverage tallies for the coach: total observed voxels and how
    /// many clear the "well covered" quality bar.
    func stats(wellCoveredAbove threshold: Float) -> (observed: Int, wellCovered: Int) {
        var well = 0
        for quality in cells.values where quality >= threshold { well += 1 }
        return (cells.count, well)
    }

    /// Mass-centre (world space) of the under-covered voxels and their
    /// count — the hook the coach turns into a "scan toward here"
    /// direction. Nil when nothing qualifies.
    func underCoveredMass(below threshold: Float) -> (centroid: SIMD3<Float>, count: Int)? {
        let half = tuning.voxelSize * 0.5
        var sum = SIMD3<Float>(repeating: 0)
        var count = 0
        for (key, quality) in cells where quality < threshold {
            let (ix, iy, iz) = Self.voxelCoords(key)
            sum += SIMD3<Float>(Float(ix), Float(iy), Float(iz)) * tuning.voxelSize + half
            count += 1
        }
        guard count > 0 else { return nil }
        return (sum / Float(count), count)
    }

    /// Take an immutable copy of the grid for off-thread export
    /// (e.g. `coverage.ply` save). Sendable; safe to hand to a detached
    /// task while the live grid keeps mutating.
    func snapshot() -> CoverageSnapshot {
        let half = tuning.voxelSize * 0.5
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(cells.count)
        for (key, quality) in cells {
            let (ix, iy, iz) = Self.voxelCoords(key)
            let center = SIMD3<Float>(Float(ix), Float(iy), Float(iz)) * tuning.voxelSize + half
            out.append(SIMD4<Float>(center.x, center.y, center.z, quality))
        }
        return CoverageSnapshot(voxelSize: tuning.voxelSize, points: out)
    }

    /// Write occupied voxel centres + quality (xyz, w) into a point
    /// buffer. Returns the number written (capped at `capacity`).
    func writePoints(into pointer: UnsafeMutablePointer<SIMD4<Float>>,
                     capacity: Int) -> Int {
        let half = tuning.voxelSize * 0.5
        var n = 0
        for (key, quality) in cells {
            if n >= capacity { break }
            let (ix, iy, iz) = Self.voxelCoords(key)
            let center = SIMD3<Float>(Float(ix), Float(iy), Float(iz)) * tuning.voxelSize + half
            pointer[n] = SIMD4<Float>(center.x, center.y, center.z, quality)
            n += 1
        }
        return n
    }

    // MARK: - Voxel key packing (21-bit signed per axis → ±52 km @ 5 cm)

    private static let axisMask: Int64 = 0x1FFFFF

    private static func voxelKey(_ fx: Float, _ fy: Float, _ fz: Float) -> Int64 {
        let ix = Int64(floor(fx))
        let iy = Int64(floor(fy))
        let iz = Int64(floor(fz))
        return ((ix & axisMask) << 42) | ((iy & axisMask) << 21) | (iz & axisMask)
    }

    private static func voxelCoords(_ key: Int64) -> (Int, Int, Int) {
        func signExtend(_ raw: Int64) -> Int {
            let m = raw & axisMask
            return Int(m >= 0x100000 ? m - 0x200000 : m)
        }
        return (signExtend(key >> 42), signExtend(key >> 21), signExtend(key))
    }
}
