//
//  ARSessionManager.swift
//  Mosaic
//
//  Owns the ARSession lifecycle. Configures world tracking with
//  classified scene reconstruction, forwards delegate events to a
//  ClassificationStats tally, and publishes user-facing state changes
//  to an injected ARMessages bus.
//
//  Logging:
//    - Log.ar.debug: per-anchor add / remove events.
//    - Log.ar.info:  rolling 2-second summary (anchor + face + class tallies).
//

import Foundation
import ARKit
import Combine
import Observation
import os

@MainActor
@Observable
final class ARSessionManager: NSObject {

    enum CameraDirection: String, Sendable, CaseIterable {
        case back, front
    }

    let session = ARSession()
    private(set) var trackingState: ARCamera.TrackingState = .notAvailable
    private(set) var isRunning: Bool = false
    private(set) var direction: CameraDirection = .back

    /// True while ARCoachingOverlayView owns the screen. We suppress
    /// our own tracking-state chips during this window to avoid
    /// double-messaging the user.
    private(set) var coachingActive: Bool = false

    /// Whether the one-shot "ready" welcome chip has fired this session.
    @ObservationIgnored private var didShowReady: Bool = false

    /// AR-scoped message bus — set by the hosting view before `start()`.
    weak var messages: ARMessages?

    @ObservationIgnored private let stats = ClassificationStats()
    @ObservationIgnored private var summaryTask: Task<Void, Never>?

    private static let summaryInterval: TimeInterval = 2.0

    override init() {
        super.init()
        session.delegate = self
    }

    // MARK: - Lifecycle

    func start() {
        let config: ARConfiguration
        switch direction {
        case .back:
            guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
                Log.ar.error("scene reconstruction with classification not supported")
                messages?.show("Device does not support scene reconstruction",
                               kind: .error, placement: .center, lifetime: .sticky)
                return
            }
            let wt = ARWorldTrackingConfiguration()
            wt.sceneReconstruction = .meshWithClassification
            wt.planeDetection = [.horizontal, .vertical]
            if type(of: wt).supportsFrameSemantics(.sceneDepth) {
                wt.frameSemantics.insert(.sceneDepth)
            }
            wt.environmentTexturing = .none
            config = wt

        case .front:
            guard ARFaceTrackingConfiguration.isSupported else {
                Log.ar.error("face tracking (front camera) not supported")
                messages?.show("Front camera AR not supported on this device",
                               kind: .error)
                return
            }
            // ARFaceTrackingConfiguration uses the TrueDepth camera
            // and still publishes ARFrame.capturedImage, so the entire
            // Metal pipeline keeps working unchanged. Just no world
            // tracking, no mesh — the filter strip becomes a selfie cam.
            config = ARFaceTrackingConfiguration()
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        Log.ar.info("ARSession started · \(self.direction.rawValue, privacy: .public)")

        // No welcome message — ARCoachingOverlayView (mounted by the
        // hosting view) handles the cold-start guidance natively.

        startSummaryLoop()
    }

    /// Flip between the back (world-tracking, mesh) and front
    /// (face-tracking) cameras. Restarts the session under the new
    /// configuration; the Metal pipeline keeps consuming
    /// ARFrame.capturedImage unchanged.
    func switchCamera(to newDirection: CameraDirection) {
        guard newDirection != direction else { return }
        Log.ar.info("camera flip → \(newDirection.rawValue, privacy: .public)")
        let wasRunning = isRunning
        if wasRunning { stop() }
        direction = newDirection
        if wasRunning { start() }
    }

    /// Called by ARCoachingOverlay when Apple's onboarding UI shows
    /// or hides. While active we suppress our own tracking chips.
    /// Also gives the welcome-chip logic a chance to fire once
    /// coaching steps aside.
    func setCoachingActive(_ active: Bool) {
        coachingActive = active
        if !active { maybeShowReady() }
    }

    /// Fire the one-shot "ready" chip the first time tracking goes
    /// `.normal` while coaching isn't already explaining things.
    /// Called from both the tracking-state delegate (clean cold
    /// start) and from coaching deactivation (recovery from limited).
    private func maybeShowReady() {
        guard !didShowReady, !coachingActive else { return }
        if case .normal = trackingState {
            didShowReady = true
            messages?.show("Ready — point at any surface to scan",
                           kind: .success, lifetime: .auto(3))
        }
    }

    func stop() {
        summaryTask?.cancel()
        summaryTask = nil
        session.pause()
        isRunning = false
        stats.reset()
        didShowReady = false
        Log.ar.info("ARSession paused")
    }

    // MARK: - Rolling summary

    private func startSummaryLoop() {
        summaryTask?.cancel()
        summaryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.summaryInterval))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let summary = self.stats.summary()
                if !summary.isEmpty {
                    Log.ar.info("mesh · \(summary, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Tracking state messaging

    private func handleTrackingState(_ state: ARCamera.TrackingState) {
        trackingState = state
        switch state {
        case .normal:
            Log.ar.info("tracking: normal")
            maybeShowReady()
        case .notAvailable:
            Log.ar.warning("tracking: not available")
            if !coachingActive {
                messages?.show("Tracking not available",
                               kind: .warning, source: "ar.tracking")
            }
        case .limited(let reason):
            let label = Self.label(reason)
            Log.ar.warning("tracking limited: \(label, privacy: .public)")
            // .initializing and .relocalizing are owned by the
            // coaching overlay — don't duplicate them in chips.
            let coveredByCoaching = (reason == .initializing || reason == .relocalizing)
            if !coachingActive && !coveredByCoaching {
                messages?.show("Tracking limited — \(label)",
                               kind: .warning, lifetime: .auto(3), source: "ar.tracking")
            }
        }
    }

    private static func label(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing:        "initializing"
        case .relocalizing:        "relocalizing"
        case .excessiveMotion:     "moving too fast"
        case .insufficientFeatures: "poor lighting or featureless surface"
        @unknown default:          "unknown reason"
        }
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for anchor in meshes {
                self.stats.update(from: anchor)
                let short = String(anchor.identifier.uuidString.prefix(8))
                Log.ar.debug("+anchor \(short, privacy: .public) faces=\(anchor.geometry.faces.count)")
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for anchor in meshes { self.stats.update(from: anchor) }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for anchor in meshes {
                self.stats.remove(anchor)
                let short = String(anchor.identifier.uuidString.prefix(8))
                Log.ar.debug("-anchor \(short, privacy: .public)")
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            Log.ar.error("session failed: \(message, privacy: .public)")
            self?.messages?.show("AR session failed — \(message)",
                                 kind: .error, priority: .critical,
                                 placement: .center, lifetime: .auto(4))
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            Log.ar.warning("session interrupted")
            self?.messages?.pin("AR session interrupted",
                                kind: .warning, placement: .center,
                                source: "ar.interrupted")
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            Log.ar.info("session interruption ended")
            self?.messages?.show("Session resumed", kind: .success,
                                 source: "ar.interrupted")
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = camera.trackingState
        Task { @MainActor [weak self] in
            self?.handleTrackingState(state)
        }
    }
}
