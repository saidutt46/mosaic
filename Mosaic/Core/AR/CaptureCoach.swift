//
//  CaptureCoach.swift
//  Mosaic
//
//  The scan-coverage guidance engine (F.2.3). Pure logic — no UIKit /
//  SwiftUI, no side effects: it reads the CoverageGrid + the camera pose
//  and produces a CoverageReport value. UI (a % readout now; arrow
//  overlays / a SceneMessageView later) consumes the report; the engine
//  never touches the screen.
//
//  Designed to grow: `Guidance` is an enum with associated data (new
//  kinds are additive), and `worldDirection` toward the under-covered
//  mass is computed from day one, so future arrow overlays / AR-view
//  aiming only have to read it.
//

import Foundation
import simd

/// One evaluation of how well-scanned the space is, plus what to do next.
struct CoverageReport: Sendable, Equatable {
    var observedVoxels: Int
    var wellCoveredVoxels: Int
    /// wellCovered / observed, in [0, 1]. The "% covered" number.
    var coverageFraction: Float
    var guidance: Guidance

    var underCoveredVoxels: Int { max(0, observedVoxels - wellCoveredVoxels) }

    static let empty = CoverageReport(
        observedVoxels: 0, wellCoveredVoxels: 0,
        coverageFraction: 0, guidance: .insufficientData
    )

    /// What the coach suggests. Additive — new cases don't break callers.
    enum Guidance: Sendable, Equatable {
        case insufficientData
        /// More to scan. `worldDirection` (unit, world space) points from
        /// the camera toward the under-covered mass when it's localised
        /// enough to aim at; nil when it's diffuse / all around.
        case scanMore(worldDirection: SIMD3<Float>?, severity: Float)
        case wellCovered
    }
}

/// Stateless evaluator. Hold one instance; call `evaluate` on a tick.
struct CaptureCoach {

    struct Tuning {
        /// Per-voxel quality at/above which a cell counts as "well covered".
        var wellCoveredQuality: Float = 0.5
        /// coverageFraction at/above which we call the scan good.
        var goodCoverageFraction: Float = 0.9
        /// Need at least this many observed voxels before advising.
        var minObservedVoxels: Int = 40
        /// Only emit a steer direction when the under-covered mass is at
        /// least this far from the camera (closer ⇒ too diffuse to aim).
        var minSteerDistance: Float = 0.3
    }

    var tuning = Tuning()

    /// Evaluate the grid against the current camera pose. Pure.
    func evaluate(grid: CoverageGrid, cameraTransform: simd_float4x4?) -> CoverageReport {
        let (observed, wellCovered) = grid.stats(wellCoveredAbove: tuning.wellCoveredQuality)

        guard observed >= tuning.minObservedVoxels else {
            return CoverageReport(
                observedVoxels: observed, wellCoveredVoxels: wellCovered,
                coverageFraction: 0, guidance: .insufficientData
            )
        }

        let fraction = Float(wellCovered) / Float(observed)

        let guidance: CoverageReport.Guidance
        if fraction >= tuning.goodCoverageFraction {
            guidance = .wellCovered
        } else {
            let severity = 1 - fraction
            let direction = steerDirection(grid: grid, cameraTransform: cameraTransform)
            guidance = .scanMore(worldDirection: direction, severity: severity)
        }

        return CoverageReport(
            observedVoxels: observed,
            wellCoveredVoxels: wellCovered,
            coverageFraction: fraction,
            guidance: guidance
        )
    }

    /// World-space unit vector from the camera toward the under-covered
    /// mass-centre — the hook for arrow overlays. Nil when there's no
    /// camera pose or the mass is too close to aim at meaningfully.
    private func steerDirection(grid: CoverageGrid,
                                cameraTransform: simd_float4x4?) -> SIMD3<Float>? {
        guard let cameraTransform,
              let mass = grid.underCoveredMass(below: tuning.wellCoveredQuality) else {
            return nil
        }
        let camCol = cameraTransform.columns.3
        let cameraPos = SIMD3<Float>(camCol.x, camCol.y, camCol.z)
        let delta = mass.centroid - cameraPos
        let distance = simd_length(delta)
        guard distance >= tuning.minSteerDistance else { return nil }
        return delta / distance
    }
}
