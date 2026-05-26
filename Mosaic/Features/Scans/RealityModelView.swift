//
//  RealityModelView.swift
//  Mosaic
//
//  Static USDZ viewer for the scan detail page, built on RealityKit
//  (CLAUDE.md §5.6 carve-out). ARView runs in .nonAR mode — there's no
//  built-in orbit, so the camera is a perspective Entity on a sphere
//  around the model centre, driven by gestures:
//    • one-finger pan  → orbit (azimuth / elevation)
//    • two-finger pan  → pan the focus point (truck/pedestal)
//    • pinch           → zoom (dolly)
//    • double-tap      → reset to the default angle + framing
//  Camera presets just set the orbit angles. Viewer only; never touches
//  the live AR/Metal pipeline.
//

import SwiftUI
import RealityKit
import ARKit

struct RealityModelView: UIViewRepresentable {
    let modelURL: URL?
    let preset: CameraPreset
    /// Bump to (re)apply `preset` (keeps current zoom).
    let presetToken: Int
    /// Bump to fully reset to the default angle + framing.
    let resetToken: Int
    /// Per-class colours (indexed by ARMeshClassification raw value).
    let palette: [SIMD4<Float>]
    /// Bit N set ⇒ class N visible.
    let visibilityMask: UInt32
    /// Whole-model opacity (0…1).
    let opacity: Float
    /// Called on the main actor once the model finishes loading (or fails).
    var onLoaded: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onLoaded: onLoaded) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.secondarySystemBackground)
        context.coordinator.install(on: arView)
        context.coordinator.setStyle(palette: palette, mask: visibilityMask, opacity: opacity)
        context.coordinator.load(modelURL)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        let c = context.coordinator
        c.setStyle(palette: palette, mask: visibilityMask, opacity: opacity)
        if c.lastResetToken != resetToken {
            c.lastResetToken = resetToken
            c.reset()
        } else if c.lastPresetToken != presetToken {
            c.lastPresetToken = presetToken
            c.apply(preset)
        }
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onLoaded: () -> Void
        private let animator = CameraAnimator()
        private weak var arView: ARView?
        private var camera: Entity?

        private var rotation = CameraPreset.default.rotation   // (elevation, azimuth)
        private var distance: Float = 2
        private var center: SIMD3<Float> = .zero

        private var defaultDistance: Float = 2
        private var defaultCenter: SIMD3<Float> = .zero
        private var minDistance: Float = 0.2
        private var maxDistance: Float = 50

        var lastPresetToken = 0
        var lastResetToken = 0

        // Layers — per-class entities (keyed by classification label) +
        // the loaded model root for opacity. Style is stored so it can
        // be (re)applied both on change and once the model loads.
        private var classEntities: [String: Entity] = [:]
        private var modelRoot: Entity?
        private var palette: [SIMD4<Float>] = []
        private var visibilityMask: UInt32 = 0xFF
        private var opacity: Float = 1

        private static let fovDegrees: Float = 55
        private static let framingFactor: Float = 1.05   // smaller = camera closer

        init(onLoaded: @escaping () -> Void) {
            self.onLoaded = onLoaded
        }

        func install(on arView: ARView) {
            self.arView = arView

            let cameraAnchor = AnchorEntity(world: .zero)
            let cam = Entity()
            cam.components.set(PerspectiveCameraComponent(
                near: 0.01, far: 200, fieldOfViewInDegrees: Self.fovDegrees))
            cameraAnchor.addChild(cam)
            arView.scene.addAnchor(cameraAnchor)
            self.camera = cam

            // Modest neutral lighting — even, not dramatic.
            let lights = AnchorEntity(world: .zero)
            let key = DirectionalLight()
            key.light.intensity = 1000
            key.look(at: .zero, from: SIMD3(1, 1.5, 1), relativeTo: nil)
            let fill = DirectionalLight()
            fill.light.intensity = 350
            fill.look(at: .zero, from: SIMD3(-1, 1, -1), relativeTo: nil)
            lights.addChild(key)
            lights.addChild(fill)
            arView.scene.addAnchor(lights)

            installGestures(on: arView)
        }

        private func installGestures(on arView: ARView) {
            let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
            orbit.maximumNumberOfTouches = 1

            let truck = UIPanGestureRecognizer(target: self, action: #selector(handleTruck(_:)))
            truck.minimumNumberOfTouches = 2
            truck.maximumNumberOfTouches = 2
            truck.delegate = self

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2

            arView.addGestureRecognizer(orbit)
            arView.addGestureRecognizer(truck)
            arView.addGestureRecognizer(pinch)
            arView.addGestureRecognizer(doubleTap)
        }

        // Let pinch (zoom) and two-finger pan (truck) run together.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func load(_ url: URL?) {
            guard let url, let arView else { onLoaded(); return }
            Task { @MainActor in
                defer { onLoaded() }
                guard let entity = try? await Entity(contentsOf: url) else { return }
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)
                modelRoot = entity

                // Our USDZ has one mesh per classification, named by label.
                classEntities = [:]
                for c in ARMeshClassification.allKnown {
                    if let e = entity.findEntity(named: c.label) { classEntities[c.label] = e }
                }
                applyStyle()

                let bounds = entity.visualBounds(relativeTo: nil)
                defaultCenter = bounds.center
                let radius = max(length(bounds.extents) / 2, 0.1)
                let halfFOV = (Self.fovDegrees / 2) * .pi / 180
                defaultDistance = radius / tan(halfFOV) * Self.framingFactor
                minDistance = defaultDistance * 0.08
                maxDistance = defaultDistance * 4
                reset()
            }
        }

        // MARK: Layers / style

        func setStyle(palette: [SIMD4<Float>], mask: UInt32, opacity: Float) {
            guard palette != self.palette || mask != visibilityMask || opacity != self.opacity else { return }
            self.palette = palette
            self.visibilityMask = mask
            self.opacity = opacity
            applyStyle()
        }

        private func applyStyle() {
            guard !classEntities.isEmpty else { return }   // model not loaded yet
            for (index, c) in ARMeshClassification.allKnown.enumerated() {
                guard let entity = classEntities[c.label] else { continue }
                entity.isEnabled = (visibilityMask & (1 << UInt32(index))) != 0
                if index < palette.count { recolor(entity, palette[index]) }
            }
            if let modelRoot {
                modelRoot.components.set(OpacityComponent(opacity: opacity))
            }
        }

        /// Re-tint every ModelComponent at or under `entity`.
        private func recolor(_ entity: Entity, _ rgba: SIMD4<Float>) {
            let color = UIColor(red: CGFloat(rgba.x), green: CGFloat(rgba.y),
                                blue: CGFloat(rgba.z), alpha: 1)
            let material = SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)
            applyMaterial(material, to: entity)
        }

        private func applyMaterial(_ material: SimpleMaterial, to entity: Entity) {
            if var model = entity.components[ModelComponent.self] {
                model.materials = Array(repeating: material, count: max(model.materials.count, 1))
                entity.components.set(model)
            }
            for child in entity.children { applyMaterial(material, to: child) }
        }

        func apply(_ preset: CameraPreset) {
            // Animate the orbit angle, keep current zoom + focus.
            animate(to: CameraAnimator.CameraState(
                rotation: preset.rotation, distance: distance, center: center))
        }

        func reset() {
            animate(to: CameraAnimator.CameraState(
                rotation: CameraPreset.default.rotation,
                distance: defaultDistance,
                center: defaultCenter))
        }

        private func animate(to target: CameraAnimator.CameraState) {
            let from = CameraAnimator.CameraState(rotation: rotation, distance: distance, center: center)
            animator.animate(from: from, to: target) { [weak self] state in
                guard let self else { return }
                rotation = state.rotation
                distance = state.distance
                center = state.center
                updateCamera()
            }
        }

        private func updateCamera() {
            guard let camera else { return }
            let elevation = rotation.x, azimuth = rotation.y
            let offset = SIMD3<Float>(
                distance * sin(elevation) * cos(azimuth),
                distance * cos(elevation),
                distance * sin(elevation) * sin(azimuth)
            )
            let position = center + offset
            camera.position = position
            camera.look(at: center, from: position, relativeTo: nil)
        }

        // MARK: Gestures

        @objc private func handleOrbit(_ g: UIPanGestureRecognizer) {
            animator.cancel()
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            let sensitivity: Float = 0.007
            rotation.y += Float(t.x) * sensitivity
            rotation.x = min(max(rotation.x - Float(t.y) * sensitivity, 0.05), .pi - 0.05)
            updateCamera()
        }

        @objc private func handleTruck(_ g: UIPanGestureRecognizer) {
            guard let camera else { return }
            animator.cancel()
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            // Move the focus point in the camera's screen plane so the
            // model follows the fingers. Scale by distance for even feel.
            let m = camera.transform.matrix
            let right = SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z)
            let up = SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z)
            let k = distance * 0.0015
            center += (-right * Float(t.x) + up * Float(t.y)) * k
            updateCamera()
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            animator.cancel()
            distance = min(max(distance / Float(g.scale), minDistance), maxDistance)
            g.scale = 1
            updateCamera()
        }

        @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
            reset()
        }

        func cleanup() {
            animator.cancel()
            arView?.scene.anchors.removeAll()
            arView = nil
            camera = nil
            modelRoot = nil
            classEntities = [:]
        }
    }
}
