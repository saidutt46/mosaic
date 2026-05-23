//
//  ARCoachingOverlay.swift
//  Mosaic
//
//  SwiftUI wrapper around Apple's ARCoachingOverlayView — the
//  polished native onboarding/relocalization UI ("Move your phone
//  around", "Find a surface…"). Activates automatically when ARKit
//  needs guidance and deactivates when tracking is healthy.
//
//  We route activate/deactivate through a closure so the hosting
//  view can suppress redundant ARMessages chips while coaching owns
//  the screen.
//

import SwiftUI
import ARKit
import os

struct ARCoachingOverlay: UIViewRepresentable {
    let session: ARSession
    let onActiveChange: @MainActor (Bool) -> Void
    var goal: ARCoachingOverlayView.Goal = .tracking

    func makeCoordinator() -> Coordinator {
        Coordinator(onActiveChange: onActiveChange)
    }

    func makeUIView(context: Context) -> ARCoachingOverlayView {
        let view = ARCoachingOverlayView(frame: .zero)
        view.session = session
        view.delegate = context.coordinator
        view.goal = goal
        view.activatesAutomatically = true
        return view
    }

    func updateUIView(_ uiView: ARCoachingOverlayView, context: Context) {
        if uiView.goal != goal { uiView.goal = goal }
    }

    final class Coordinator: NSObject, ARCoachingOverlayViewDelegate {
        let onActiveChange: @MainActor (Bool) -> Void

        init(onActiveChange: @escaping @MainActor (Bool) -> Void) {
            self.onActiveChange = onActiveChange
        }

        func coachingOverlayViewWillActivate(_ view: ARCoachingOverlayView) {
            Task { @MainActor in
                Log.ar.info("coaching: will activate")
                self.onActiveChange(true)
            }
        }

        func coachingOverlayViewDidDeactivate(_ view: ARCoachingOverlayView) {
            Task { @MainActor in
                Log.ar.info("coaching: did deactivate")
                self.onActiveChange(false)
            }
        }
    }
}
