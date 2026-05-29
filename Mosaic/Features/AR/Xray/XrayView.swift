//
//  XrayView.swift
//  Mosaic
//
//  Track B experience — the semantic mesh overlay. ARKit's
//  classified scene mesh rendered in Metal over the live camera,
//  per-class colored (cyan walls, green floors, …). Owns its own
//  ARSessionManager + ARMessages + capture trigger; entirely
//  separate from FiltersView so each can iterate independently.
//
//  No filter strip, no camera flip (mesh anchors are tied to the
//  back camera + LiDAR). Chrome focuses on mesh interaction:
//
//   - Top bar:     close (X) · mesh-stats capsule
//   - Right HUD:   density · presets · classes · photo · fill-mode
//                  (ViewerControlButton glass cluster; active toggles
//                   tint accent)
//   - Bottom bar:  Done (primary) → review sheet → save
//

import SwiftUI
import simd
import os

struct XrayView: View {
    /// Called after a scan is saved — the host routes to its detail view.
    var onComplete: (Scan) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var sessionManager = ARSessionManager()
    @State private var messages = ARMessages()
    @State private var stats = MeshStatsModel()
    @State private var meshFillMode: MeshOverlayPass.FillMode = .wireframe
    @State private var meshDensity: MeshDensity = .full
    @State private var meshFresnelIntensity: Float = 0.0
    @State private var meshOpacity: Float = 0.55
    @State private var meshVisualizationMode: MeshVisualizationMode = .classification
    @State private var showDepthPoints = false
    @State private var classificationStyles = ClassificationStyles()
    @Environment(AppServices.self) private var services
    private var scans: ScanRepository { services.scans }
    @State private var isSaving = false
    @State private var pendingSave: PendingSave?
    @State private var capturedThumbnail: UIImage?
    @State private var showingSaveSheet = false
    @State private var captureTrigger: Int = 0
    @State private var showingClassification = false
    @State private var showingStats = false
    @State private var showingPresets = false

    var body: some View {
        // Foreground respects the safe area (so the HUD never clips);
        // the full-bleed AR content lives in `.background`, which is
        // layout-neutral — it doesn't stretch this stack to the
        // physical screen edge the way an in-stack ignoresSafeArea
        // child would.
        ZStack(alignment: .trailing) {
            Color.clear
            hudControls
        }
        .overlay(alignment: .top) {
            if meshVisualizationMode == .coverage,
               let report = sessionManager.coverageReport {
                CoverageCapsule(report: report)
                    .padding(.top, MosaicSpacing.sm)
                    .transition(.opacity)
            }
        }
        .background {
            ZStack {
                ARMetalViewRepresentable(
                    session: sessionManager.session,
                    meshCache: sessionManager.meshCache,   // ⟵ mesh ON
                    filter: .none,                          // no camera filter in Xray
                    meshFillMode: meshFillMode,
                    meshDensity: meshDensity,
                    meshFresnelIntensity: meshFresnelIntensity,
                    meshOpacity: meshOpacity,
                    meshPalette: classificationStyles.palette,
                    meshClassVisibilityMask: classificationStyles.visibilityMask,
                    meshVisualizationMode: meshVisualizationMode,
                    showDepthPoints: showDepthPoints,
                    captureTrigger: captureTrigger,
                    onCapture: handleCapture
                )

                ARCoachingOverlay(
                    session: sessionManager.session,
                    onActiveChange: { sessionManager.setCoachingActive($0) }
                )

                ARMessageOverlay()
                    .environment(messages)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // MARK: Top bar — close (leading) · stats HUD (trailing)
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                MeshStatsCapsule(
                    faceCount: stats.faceCount,
                    fps: stats.fps
                ) {
                    showingStats = true
                }
            }
        }
        // Bottom bar — primary action only. Tools live in the
        // right-edge HUD cluster (hudControls).
        .toolbar {
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Done") {
                    handleDone()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(stats.anchorCount == 0)
                .accessibilityLabel("Done — review and save scan")
            }
        }
        .sheet(isPresented: $showingClassification) {
            XrayClassificationSheet(
                styles: classificationStyles,
                opacity: $meshOpacity
            )
        }
        .sheet(isPresented: $showingPresets) {
            XrayPresetSheet { preset in
                applyPreset(preset)
            }
        }
        .sheet(isPresented: $showingStats) {
            MeshStatsSheet(
                faceCount: stats.faceCount,
                anchorCount: stats.anchorCount,
                fps: stats.fps,
                density: $meshDensity,
                fresnelIntensity: $meshFresnelIntensity
            )
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveScanSheet(
                stats: pendingSave?.stats ?? (anchors: 0, faces: 0, vertices: 0),
                extent: pendingSave?.extent,
                coverage: pendingSave?.coverage,
                duration: pendingSave?.duration ?? 0,
                classCounts: pendingSave?.classCounts ?? [:],
                palette: pendingSave?.palette ?? MeshOverlayPass.defaultPalette,
                isSaving: isSaving,
                onSave: performSave,
                onClose: handleCloseSession,
                onResume: handleResume
            )
        }
        .onAppear {
            sessionManager.messages = messages
            sessionManager.start()
            stats.meshCache = sessionManager.meshCache
            stats.start()
        }
        .onDisappear {
            stats.stop()
            sessionManager.stop()
            messages.clearAll()
        }
    }

    // MARK: - HUD controls (right-edge cluster)

    private var hudControls: some View {
        VStack(spacing: MosaicSpacing.md) {
            ViewerControlMenu(
                title: meshVisualizationMode.label,
                icon: "point.3.connected.trianglepath.dotted",
                isActive: meshVisualizationMode != .classification,
                animatesWhenActive: true
            ) {
                Picker("Mesh shading", selection: $meshVisualizationMode) {
                    ForEach(MeshVisualizationMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                Divider()
                Toggle(isOn: $showDepthPoints) {
                    Label("Coverage points (debug)", systemImage: "circle.dotted")
                }
            }

            ViewerControlButton(title: "Presets", icon: "sparkles") {
                showingPresets = true
            }

            ViewerControlButton(title: "Classes", icon: "paintpalette.fill") {
                showingClassification = true
            }

            ViewerControlButton(title: "Photo", icon: "camera.fill") {
                captureTrigger &+= 1
            }

            ViewerControlButton(
                title: meshFillMode == .filled ? "Solid" : "Wire",
                icon: meshFillMode == .filled ? "cube.fill" : "cube.transparent",
                isActive: meshFillMode == .wireframe
            ) {
                withAnimation(MosaicMotion.snappy) {
                    meshFillMode = (meshFillMode == .filled) ? .wireframe : .filled
                }
            }
        }
        .padding(.trailing, MosaicSpacing.lg)
    }

    // MARK: - Preset apply

    @MainActor
    private func applyPreset(_ preset: MeshPreset) {
        withAnimation(MosaicMotion.smooth) {
            meshFillMode = preset.fillMode
            meshDensity = preset.density
            meshOpacity = preset.opacity
            meshFresnelIntensity = preset.fresnelIntensity
            preset.apply(to: classificationStyles)
        }
    }

    // MARK: - Snapshot derivations (save-sheet stats)

    /// World-axis-aligned extent (metres) of every transformed vertex in
    /// the snapshot. Nil when the snapshot has no vertices to measure.
    /// "Extent" not "room size" — outdoor scans are valid too.
    private static func scanExtent(of snapshot: [MeshAnchorBuffers]) -> SIMD3<Float>? {
        var minP = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var any = false
        for buffers in snapshot {
            let verts = buffers.vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self)
            let transform = buffers.transform
            for v in 0..<buffers.vertexCount {
                let local = verts[v]
                let w = transform * SIMD4<Float>(local, 1)
                let p = SIMD3<Float>(w.x, w.y, w.z)
                minP = simd_min(minP, p)
                maxP = simd_max(maxP, p)
                any = true
            }
        }
        return any ? (maxP - minP) : nil
    }

    /// Per-class face counts keyed by `ARMeshClassification` raw value.
    private static func classCounts(of snapshot: [MeshAnchorBuffers]) -> [UInt8: Int] {
        var counts: [UInt8: Int] = [:]
        for buffers in snapshot {
            guard let cls = buffers.classificationBuffer?
                .contents().assumingMemoryBound(to: UInt8.self) else { continue }
            for f in 0..<buffers.faceCount {
                counts[cls[f], default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Save handling

    /// Snapshot taken at the moment of the Save tap. Held while we wait
    /// one frame for the thumbnail capture to come back.
    private struct PendingSave {
        let snapshot: [MeshAnchorBuffers]
        let stats: (anchors: Int, faces: Int, vertices: Int)
        let palette: [SIMD4<Float>]
        /// Coverage voxel snapshot — nil/empty when coverage/coach wasn't
        /// used this session; in that case no `coverage.ply` is written.
        let coverage: CoverageSnapshot?
        /// World-axis-aligned scan extent (metres) from snapshot vertices.
        /// Nil when the snapshot has nothing to measure.
        let extent: SIMD3<Float>?
        /// Per-face counts keyed by `ARMeshClassification` raw value.
        let classCounts: [UInt8: Int]
        /// Active capture wall-time (paused intervals excluded).
        let duration: TimeInterval
    }

    /// Done — snapshot the scan and request a composited frame; the
    /// review sheet opens once that frame arrives in handleCapture.
    @MainActor
    private func handleDone() {
        let cache = sessionManager.meshCache
        let snapshot = cache.snapshot
        guard !snapshot.isEmpty else {
            messages.show("Nothing to save yet", kind: .warning)
            return
        }
        let coverage = cache.coverageGrid.snapshot()
        pendingSave = PendingSave(
            snapshot: snapshot,
            stats: (anchors: cache.anchorCount,
                    faces: cache.totalFaceCount,
                    vertices: cache.totalVertexCount),
            palette: classificationStyles.palette,
            coverage: coverage.isEmpty ? nil : coverage,
            extent: Self.scanExtent(of: snapshot),
            classCounts: Self.classCounts(of: snapshot),
            duration: sessionManager.activeScanDuration
        )
        captureTrigger &+= 1
    }

    /// Commit the pending scan. On success, hand the saved scan to the
    /// host so it can route to the detail viewer.
    @MainActor
    private func performSave() {
        guard let pending = pendingSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let scan = try await scans.save(snapshot: pending.snapshot,
                                                stats: pending.stats,
                                                palette: pending.palette,
                                                coverage: pending.coverage,
                                                thumbnail: capturedThumbnail)
                showingSaveSheet = false
                clearPending()
                onComplete(scan)
            } catch {
                messages.show("Couldn't save scan", kind: .error)
                Log.app.error("scan save (ui): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Discard the session entirely — nothing was written yet.
    @MainActor
    private func handleCloseSession() {
        showingSaveSheet = false
        clearPending()
        dismiss()
    }

    /// Keep scanning — resume the paused session, drop the snapshot.
    @MainActor
    private func handleResume() {
        showingSaveSheet = false
        clearPending()
        sessionManager.resumeFromReview()
    }

    private func clearPending() {
        pendingSave = nil
        capturedThumbnail = nil
    }

    // MARK: - Capture handling

    @MainActor
    private func handleCapture(_ image: UIImage?) {
        // Finishing a scan: grab the composited frame as the thumbnail,
        // freeze the session, and open the review sheet.
        if pendingSave != nil {
            capturedThumbnail = image.map { Self.thumbnail(from: $0) }
            sessionManager.pauseForReview()
            showingSaveSheet = true
            return
        }
        guard let image else {
            messages.show("Capture failed", kind: .error)
            return
        }
        PhotoCapture.save(image) { result in
            switch result {
            case .success:
                messages.show("Saved to Photos",
                              kind: .success,
                              icon: "photo.badge.checkmark")
            case .failure(.notAuthorized):
                messages.show("Photos access denied",
                              kind: .warning,
                              lifetime: .auto(4))
            case .failure(.underlying):
                messages.show("Couldn't save photo", kind: .error)
            }
        }
    }

    /// Downscale the full-res composited frame to a library thumbnail.
    private static func thumbnail(from image: UIImage, maxDimension: CGFloat = 512) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale,
                          height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
