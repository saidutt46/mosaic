//
//  ARView.swift
//  Mosaic
//
//  The AR experience root. Owns the ARSessionManager + ARMessages bus
//  for this presentation. Renders the live ARSCNView underneath the
//  coaching overlay and the AR message overlay. Chrome is a native
//  iOS 26 toolbar with Liquid Glass buttons (leading close + trailing
//  help) floating over the scene.
//

import SwiftUI
import os

struct ARView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var sessionManager = ARSessionManager()
    @State private var messages = ARMessages()

    var body: some View {
        ZStack {
            ARSceneView(
                session: sessionManager.session,
                showDebug: settings.showDebugOverlay
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .tint(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
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
