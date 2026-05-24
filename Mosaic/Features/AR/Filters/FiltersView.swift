//
//  FiltersView.swift
//  Mosaic
//
//  Track A experience — the camera-filter playground. Owns the
//  ARSessionManager + ARMessages bus + active CameraFilter +
//  capture trigger for this presentation. Renders the live camera
//  through the Metal pipeline with the user-selected fragment
//  shader; coaching + message overlays layered above; filter strip
//  pinned to the bottom safe area.
//
//  The mesh overlay is intentionally OFF here — FiltersView passes
//  `meshCache: nil` to the renderer so the mesh pass is skipped.
//  Track B's XrayView turns it on.
//
//  Chrome:
//   - Toolbar leading:  close (X)
//   - Toolbar trailing: capture · flip (if supported) · reset
//                       (if filter active) · help
//     iOS 26 ToolbarSpacer(.fixed) separates each into its own
//     Liquid Glass pill instead of merging.
//   - Bottom safe-area: CameraFilterStrip.
//

import SwiftUI
import ARKit
import os

struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionManager = ARSessionManager()
    @State private var messages = ARMessages()
    @State private var filter: CameraFilter = .none
    @State private var captureTrigger: Int = 0

    /// Snapshot at view init — face tracking support doesn't change
    /// at runtime, so hide the flip button entirely on devices that
    /// can't do front-camera AR.
    private let isFrontCameraSupported = ARFaceTrackingConfiguration.isSupported

    var body: some View {
        ZStack {
            ARMetalViewRepresentable(
                session: sessionManager.session,
                meshCache: nil,                // ⟵ no mesh in Filters
                filter: filter,
                meshFillMode: .filled,         // ignored when meshCache is nil
                meshDensity: .full,            // ignored when meshCache is nil
                meshFresnelIntensity: 0.0,     // ignored when meshCache is nil
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CameraFilterStrip(selection: $filter)
                .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    captureTrigger &+= 1
                } label: {
                    Image(systemName: "camera.fill")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            if isFrontCameraSupported {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let next: ARSessionManager.CameraDirection =
                            sessionManager.direction == .back ? .front : .back
                        sessionManager.switchCamera(to: next)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            if filter != .none {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(MosaicMotion.snappy) {
                            filter = .none
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // TODO: filter help / quick-settings panel.
                    Log.ui.debug("Filters help button tapped (no-op)")
                } label: {
                    Image(systemName: "questionmark")
                }
            }
        }
        .onAppear {
            sessionManager.messages = messages
            sessionManager.start()
        }
        .onDisappear {
            sessionManager.stop()
            messages.clearAll()
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
