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

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = true
        view.rendersContinuously = true
        // ARKit doesn't provide a built-in scene-mesh wireframe debug option.
        // Phase 5 verifies classification via logs; Phase 6 will render the
        // mesh in Metal. Feature points are useful for spotting tracking gaps.
        view.debugOptions = [ARSCNDebugOptions.showFeaturePoints,
                             ARSCNDebugOptions.showWorldOrigin]
        view.scene = SCNScene()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
