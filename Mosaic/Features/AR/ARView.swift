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
import os

struct ARView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionManager = ARSessionManager()
    @State private var messages = ARMessages()
    @State private var filter: CameraFilter = .none

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
                .tint(.white)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if filter != .none {
                    Button {
                        withAnimation(MosaicMotion.snappy) {
                            filter = .none
                        }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .tint(.white)
                }
                Button {
                    // TODO: AR help / quick-settings panel.
                    Log.ui.debug("AR help button tapped (no-op)")
                } label: {
                    Image(systemName: "questionmark")
                }
                .tint(.white)
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
