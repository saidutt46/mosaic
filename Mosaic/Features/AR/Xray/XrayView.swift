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
//   - Toolbar leading:  close (X)
//   - Toolbar trailing: fill-mode toggle (wireframe ↔ filled)
//   - Bottom bar leading:  capture
//   - Bottom bar trailing: palette (stub sheet for B.4.x)
//
//  Future polish: FPS HUD, anchor / triangle count badge, palette
//  picker proper, mesh on/off, scan-line / Fresnel styles.
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

            // MARK: Bottom bar — leading area reserved for future
            // option groups (density, opacity, effects). Right
            // cluster keeps the action controls: palette · capture
            // · fill-mode toggle.
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
