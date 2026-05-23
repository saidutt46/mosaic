//
//  ARMetalViewRepresentable.swift
//  Mosaic
//
//  SwiftUI wrapper around MTKView. Owns the Renderer for the
//  lifetime of the AR experience — MTKView holds its delegate
//  weakly, so the Coordinator keeps a strong reference.
//
//  Exposes the current camera filter as a parameter; updateUIView
//  pushes changes down to the Renderer (which forwards to the
//  CameraBackgroundPass pipeline-state cache).
//

import SwiftUI
import MetalKit
import ARKit

struct ARMetalViewRepresentable: UIViewRepresentable {
    let session: ARSession
    let filter: CameraFilter

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        let renderer = Renderer(view: view, session: session)
        renderer.setFilter(filter)
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.setFilter(filter)
    }

    @MainActor
    final class Coordinator {
        var renderer: Renderer?
    }
}
