//
//  ARMetalViewRepresentable.swift
//  Mosaic
//
//  SwiftUI wrapper around MTKView. Owns the Renderer for the
//  lifetime of the AR experience — MTKView holds its delegate
//  weakly, so the Coordinator keeps a strong reference.
//
//  - filter        : current camera-filter selection, pushed each update.
//  - captureTrigger: bump (e.g. captureTrigger += 1) to request a
//                    snapshot of the composited drawable.
//  - onCapture     : invoked on the main queue with the resulting
//                    UIImage (or nil on failure).
//

import SwiftUI
import MetalKit
import ARKit
import UIKit

struct ARMetalViewRepresentable: UIViewRepresentable {
    let session: ARSession
    /// Optional — when nil, the mesh overlay pass is skipped entirely.
    /// FiltersView passes nil; XrayView passes its session manager's cache.
    let meshCache: MeshAnchorBufferCache?
    let filter: CameraFilter
    let meshFillMode: MeshOverlayPass.FillMode
    let meshDensity: MeshDensity
    let meshFresnelIntensity: Float
    let meshOpacity: Float
    let meshPalette: [SIMD4<Float>]
    let meshClassVisibilityMask: UInt32
    let meshVisualizationMode: MeshVisualizationMode
    let captureTrigger: Int
    let onCapture: @MainActor (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        let renderer = Renderer(view: view, session: session, meshCache: meshCache)
        renderer.setFilter(filter)
        renderer.setMeshFillMode(meshFillMode)
        renderer.setMeshDensity(meshDensity)
        renderer.setMeshFresnelIntensity(meshFresnelIntensity)
        renderer.setMeshOpacity(meshOpacity)
        renderer.setMeshPalette(meshPalette)
        renderer.setMeshClassVisibility(meshClassVisibilityMask)
        renderer.setMeshVisualizationMode(meshVisualizationMode)
        context.coordinator.renderer = renderer
        context.coordinator.lastCaptureTrigger = captureTrigger
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.setFilter(filter)
        context.coordinator.renderer?.setMeshFillMode(meshFillMode)
        context.coordinator.renderer?.setMeshDensity(meshDensity)
        context.coordinator.renderer?.setMeshFresnelIntensity(meshFresnelIntensity)
        context.coordinator.renderer?.setMeshOpacity(meshOpacity)
        context.coordinator.renderer?.setMeshPalette(meshPalette)
        context.coordinator.renderer?.setMeshClassVisibility(meshClassVisibilityMask)
        context.coordinator.renderer?.setMeshVisualizationMode(meshVisualizationMode)

        if captureTrigger != context.coordinator.lastCaptureTrigger {
            context.coordinator.lastCaptureTrigger = captureTrigger
            let callback = onCapture
            context.coordinator.renderer?.requestCapture { image in
                Task { @MainActor in callback(image) }
            }
        }
    }

    @MainActor
    final class Coordinator {
        var renderer: Renderer?
        var lastCaptureTrigger: Int = 0
    }
}
