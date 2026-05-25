//
//  SceneKitModelView.swift
//  Mosaic
//
//  Static 3D model viewer surface for the saved-scan detail page.
//  Renders the USDZ mesh or the PLY point cloud with free orbit /
//  pinch via SceneKit. This is the one sanctioned SceneKit use
//  (CLAUDE.md §5.6) — it never touches the live AR/Metal pipeline.
//

import SwiftUI
import SceneKit
import SceneKit.ModelIO
import ModelIO

struct SceneKitModelView: UIViewRepresentable {
    let meshURL: URL?
    let pointCloudURL: URL?
    let showPointCloud: Bool
    /// Render the loaded mesh as a wireframe (material fillMode = .lines).
    let wireframe: Bool
    /// Bump to re-frame the camera on the model.
    let resetToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        load(into: view, context: context)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.loadedPointCloud != showPointCloud {
            load(into: view, context: context)
        }
        if context.coordinator.lastWireframe != wireframe {
            context.coordinator.lastWireframe = wireframe
            applyFillMode(to: view.scene)
        }
        if context.coordinator.lastReset != resetToken {
            context.coordinator.lastReset = resetToken
            frame(view)
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        // Stop the render loop and drop the scene so its geometry/textures
        // are released promptly when the viewer is dismissed.
        view.isPlaying = false
        view.scene = nil
    }

    // MARK: - Loading

    private func load(into view: SCNView, context: Context) {
        context.coordinator.loadedPointCloud = showPointCloud
        view.scene = showPointCloud
            ? Self.pointCloudScene(pointCloudURL)
            : Self.meshScene(meshURL)
        context.coordinator.lastWireframe = wireframe
        applyFillMode(to: view.scene)
        frame(view)
    }

    /// Toggle solid ↔ wireframe by switching every material's fill mode.
    /// Point clouds are left alone (no surfaces to wireframe).
    private func applyFillMode(to scene: SCNScene?) {
        guard let scene, !showPointCloud else { return }
        let mode: SCNFillMode = wireframe ? .lines : .fill
        scene.rootNode.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { $0.fillMode = mode }
        }
    }

    private func frame(_ view: SCNView) {
        guard let root = view.scene?.rootNode else { return }
        // Defer so SceneKit has the geometry bounds ready.
        DispatchQueue.main.async {
            view.defaultCameraController.frameNodes([root])
        }
    }

    private static func meshScene(_ url: URL?) -> SCNScene? {
        guard let url else { return nil }
        return try? SCNScene(url: url)
    }

    private static func pointCloudScene(_ url: URL?) -> SCNScene? {
        guard let url else { return nil }
        let scene = SCNScene(mdlAsset: MDLAsset(url: url))
        // PLY comes in as point primitives; size them for visibility and
        // drop lighting so the per-vertex classification colours show flat.
        scene.rootNode.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for element in geometry.elements {
                element.pointSize = 6
                element.minimumPointScreenSpaceRadius = 2
                element.maximumPointScreenSpaceRadius = 8
            }
            for material in geometry.materials {
                material.lightingModel = .constant
                material.isDoubleSided = true
            }
        }
        return scene
    }

    final class Coordinator {
        var loadedPointCloud = false
        var lastWireframe = false
        var lastReset = 0
    }
}
