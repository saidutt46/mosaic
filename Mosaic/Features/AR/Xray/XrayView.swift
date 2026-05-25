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
//   - Top bar:    close (X) · mesh-stats capsule
//   - Bottom bar: presets · classification · save · capture · fill-mode
//
//  Save (square.and.arrow.down) snapshots the current mesh to a USDZ
//  scan via ScanRepository; disabled until the mesh has anchors.
//

import SwiftUI
import os

struct XrayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionManager = ARSessionManager()
    @State private var messages = ARMessages()
    @State private var stats = MeshStatsModel()
    @State private var meshFillMode: MeshOverlayPass.FillMode = .wireframe
    @State private var meshDensity: MeshDensity = .full
    @State private var meshFresnelIntensity: Float = 0.0
    @State private var meshOpacity: Float = 0.55
    @State private var classificationStyles = ClassificationStyles()
    @State private var scans = ScanRepository()
    @State private var isSaving = false
    @State private var captureTrigger: Int = 0
    @State private var showingClassification = false
    @State private var showingStats = false
    @State private var showingPresets = false

    var body: some View {
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
                captureTrigger: captureTrigger,
                onCapture: handleCapture
            )
            .ignoresSafeArea()

            ARCoachingOverlay(
                session: sessionManager.session,
                onActiveChange: { sessionManager.setCoachingActive($0) }
            )
            .ignoresSafeArea()

            ARMessageOverlay()
                .environment(messages)
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
        // Bottom bar kept in its own .toolbar — the ToolbarContentBuilder
        // caps at 10 elements, and the separate-pill layout (spacers
        // between each item) puts this cluster right at that limit.
        .toolbar {
            // MARK: Bottom bar — action cluster: presets · classification
            // · save · capture · fill-mode. Spacers render each as its
            // own Liquid Glass pill.
            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    showingPresets = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("Style presets")
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    showingClassification = true
                } label: {
                    Image(systemName: "paintpalette.fill")
                }
                .accessibilityLabel("Classification")
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    handleSave()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(stats.anchorCount == 0 || isSaving)
                .accessibilityLabel("Save scan")
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    captureTrigger &+= 1
                } label: {
                    Image(systemName: "camera.fill")
                }
                .accessibilityLabel("Capture")
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    withAnimation(MosaicMotion.snappy) {
                        meshFillMode = (meshFillMode == .filled) ? .wireframe : .filled
                    }
                } label: {
                    Image(systemName: meshFillMode == .filled
                          ? "cube.fill"
                          : "cube.transparent")
                }
                .accessibilityLabel(meshFillMode == .filled ? "Switch to wireframe" : "Switch to filled")
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

    // MARK: - Save handling

    @MainActor
    private func handleSave() {
        let cache = sessionManager.meshCache
        let snapshot = cache.snapshot
        guard !snapshot.isEmpty else {
            messages.show("Nothing to save yet", kind: .warning)
            return
        }

        // Snapshot stats + palette at the moment of click.
        let stats = (anchors: cache.anchorCount,
                     faces: cache.totalFaceCount,
                     vertices: cache.totalVertexCount)
        let palette = classificationStyles.palette

        isSaving = true
        let savingID = messages.pin("Saving scan…", icon: "square.and.arrow.down")

        Task {
            defer { isSaving = false }
            do {
                try await scans.save(snapshot: snapshot,
                                     stats: stats,
                                     palette: palette,
                                     thumbnail: nil)   // captured in E.1.3
                messages.dismiss(savingID)
                messages.show("Scan saved", kind: .success)
            } catch {
                messages.dismiss(savingID)
                messages.show("Couldn't save scan", kind: .error)
                Log.app.error("scan save (ui): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Capture handling

    @MainActor
    private func handleCapture(_ image: UIImage?) {
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
}
