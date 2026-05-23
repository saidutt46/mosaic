//
//  ARSceneView.swift
//  Mosaic
//
//  Thin UIViewRepresentable around ARSCNView. Phase 5 leans on
//  ARKit's built-in debug rendering of the scene mesh so we can
//  visually confirm classification is working before Phase 6 replaces
//  this with our own MTKView + Metal pipeline.
//

import SwiftUI
import ARKit
import SceneKit

struct ARSceneView: UIViewRepresentable {
    let session: ARSession
    var showDebug: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = true
        view.rendersContinuously = true
        view.scene = SCNScene()
        view.debugOptions = Self.debugOptions(showDebug: showDebug)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        let options = Self.debugOptions(showDebug: showDebug)
        if uiView.debugOptions != options {
            uiView.debugOptions = options
        }
    }

    /// Feature points (the yellow tracking sparkles) are always on — they
    /// give the user real feedback that the camera is finding the scene.
    /// The world-origin XYZ axis is dev-only; gated by the settings toggle.
    private static func debugOptions(showDebug: Bool) -> SCNDebugOptions {
        var options: SCNDebugOptions = [ARSCNDebugOptions.showFeaturePoints]
        if showDebug {
            options.insert(ARSCNDebugOptions.showWorldOrigin)
        }
        return options
    }
}
