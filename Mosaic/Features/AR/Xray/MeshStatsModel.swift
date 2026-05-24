//
//  MeshStatsModel.swift
//  Mosaic
//
//  Live HUD data for XrayView. Owns a frame-rate counter (driven
//  by CADisplayLink, so it reflects what the user actually sees)
//  and samples the mesh cache once per second on a Timer.
//
//  SwiftUI re-renders only the @Observable properties' consumers
//  — the toolbar pill stays put; just the Text values inside diff.
//

import Foundation
import SwiftUI
import QuartzCore
import Observation

@MainActor
@Observable
final class MeshStatsModel {

    private(set) var faceCount: Int = 0
    private(set) var anchorCount: Int = 0
    private(set) var fps: Double?

    /// Set by the hosting view before `start()`.
    var meshCache: MeshAnchorBufferCache?

    @ObservationIgnored private var frameRate: FrameRateCounter?
    @ObservationIgnored private var sampleTimer: Timer?

    func start() {
        let counter = FrameRateCounter()
        counter.start()
        frameRate = counter

        // Sample once per second — fast enough to feel live, slow
        // enough to keep the toolbar Text diffs cheap.
        sampleTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
    }

    func stop() {
        frameRate?.stop()
        frameRate = nil
        sampleTimer?.invalidate()
        sampleTimer = nil
        faceCount = 0
        anchorCount = 0
        fps = nil
    }

    private func sample() {
        if let f = frameRate?.consume() {
            fps = f
        }
        if let cache = meshCache {
            faceCount = cache.totalFaceCount
            anchorCount = cache.anchorCount
        }
    }
}

// MARK: - Frame rate counter

/// Counts CADisplayLink ticks since the last `consume()` call and
/// returns the corresponding frames-per-second figure. Lives outside
/// MeshStatsModel as a `@MainActor NSObject` because CADisplayLink
/// requires an @objc selector target.
@MainActor
final class FrameRateCounter: NSObject {
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    private var intervalStart: CFTimeInterval = CACurrentMediaTime()

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        intervalStart = CACurrentMediaTime()
        frameCount = 0
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// FPS since the last call, then resets the interval. Returns
    /// nil on the very first call before any frames are counted.
    func consume() -> Double? {
        let now = CACurrentMediaTime()
        let elapsed = now - intervalStart
        guard elapsed > 0, frameCount > 0 else {
            intervalStart = now
            return nil
        }
        let fps = Double(frameCount) / elapsed
        frameCount = 0
        intervalStart = now
        return fps
    }

    @objc private func tick() {
        frameCount += 1
    }
}
