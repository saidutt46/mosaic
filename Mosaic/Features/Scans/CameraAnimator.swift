//
//  CameraAnimator.swift
//  Mosaic
//
//  Smooth camera transitions for the detail viewer. Interpolates a
//  camera state (orbit rotation, distance, focus centre) over time via
//  CADisplayLink, with easing and shortest-path azimuth wrap so presets
//  and reset glide instead of snapping. Framework-agnostic — the caller
//  applies each interpolated state to its own camera in `onUpdate`.
//
//  Adapted from the Oareo viewer's CameraAnimator.
//

import Foundation
import QuartzCore
import simd

@MainActor
final class CameraAnimator {

    struct CameraState {
        let rotation: SIMD2<Float>   // (elevation, azimuth) radians
        let distance: Float
        let center: SIMD3<Float>
    }

    nonisolated static let defaultDuration: TimeInterval = 0.5

    private(set) var isAnimating = false

    private var displayLink: CADisplayLink?
    private var startState: CameraState?
    private var targetState: CameraState?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = defaultDuration
    private var onUpdate: ((CameraState) -> Void)?

    func animate(from: CameraState,
                 to: CameraState,
                 duration: TimeInterval = defaultDuration,
                 update: @escaping (CameraState) -> Void) {
        cancel()
        startState = from
        targetState = to
        self.duration = duration
        onUpdate = update
        startTime = CACurrentMediaTime()
        isAnimating = true

        let link = CADisplayLink(target: DisplayLinkTarget(animator: self),
                                 selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        guard isAnimating else { return }
        displayLink?.invalidate()
        displayLink = nil
        isAnimating = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let from = startState, let to = targetState else { cancel(); return }

        let raw = Float(min((link.timestamp - startTime) / duration, 1))
        let t = easeInOutCubic(raw)
        onUpdate?(interpolate(from: from, to: to, progress: t))

        if raw >= 1 {
            displayLink?.invalidate()
            displayLink = nil
            isAnimating = false
        }
    }

    private func interpolate(from: CameraState, to: CameraState, progress t: Float) -> CameraState {
        // Shortest-path azimuth (wrap at ±π).
        var dAzimuth = to.rotation.y - from.rotation.y
        if dAzimuth > .pi { dAzimuth -= 2 * .pi }
        else if dAzimuth < -.pi { dAzimuth += 2 * .pi }

        return CameraState(
            rotation: SIMD2(from.rotation.x + (to.rotation.x - from.rotation.x) * t,
                            from.rotation.y + dAzimuth * t),
            distance: from.distance + (to.distance - from.distance) * t,
            center: from.center + (to.center - from.center) * t
        )
    }

    private func easeInOutCubic(_ t: Float) -> Float {
        t < 0.5 ? 4 * t * t * t : 1 + pow(2 * t - 2, 3) / 2
    }
}

// Weak wrapper so the display link doesn't retain the animator.
@MainActor
private final class DisplayLinkTarget {
    weak var animator: CameraAnimator?
    init(animator: CameraAnimator) { self.animator = animator }

    @objc func tick(_ link: CADisplayLink) {
        animator?.tick(link)
    }
}
