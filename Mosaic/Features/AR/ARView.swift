//
//  ARView.swift
//  Mosaic
//
//  The AR experience root. Owns the ARSessionManager + ARMessages
//  bus + active CameraFilter for this presentation. Renders the
//  live camera through our Metal pipeline, with coaching + message
//  overlays layered above, a native iOS 26 toolbar floating over
//  the top (leading close, trailing help + conditional clear), and
//  the filter strip pinned to the bottom safe area.
//

import SwiftUI
import ARKit
import os

struct ARView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionManager = ARSessionManager()
    @State private var messages = ARMessages()
    @State private var filter: CameraFilter = .none

    /// Snapshot at view init — face tracking support doesn't change
    /// at runtime, so hide the flip button entirely on devices that
    /// can't do front-camera AR.
    private let isFrontCameraSupported = ARFaceTrackingConfiguration.isSupported

    var body: some View {
        ZStack {
            ARMetalViewRepresentable(
                session: sessionManager.session,
                filter: filter
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
                // iOS 26 fixed spacer separates the reset and help
                // items into their own Liquid Glass capsules instead
                // of merging them into one combined pill.
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // TODO: AR help / quick-settings panel.
                    Log.ui.debug("AR help button tapped (no-op)")
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
}
