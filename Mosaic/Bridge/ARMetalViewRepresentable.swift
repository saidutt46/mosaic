//
//  ARMetalViewRepresentable.swift
//  Mosaic
//
//  SwiftUI wrapper around MTKView. Owns the Renderer for the
//  lifetime of the AR experience — MTKView holds its delegate
//  weakly, so the Coordinator keeps a strong reference.
//

import SwiftUI
import MetalKit
import ARKit

struct ARMetalViewRepresentable: UIViewRepresentable {
    let session: ARSession

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        let renderer = Renderer(view: view, session: session)
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Renderer reads session.currentFrame each draw — nothing
        // to push down on view updates yet.
    }

    @MainActor
    final class Coordinator {
        var renderer: Renderer?
    }
}
