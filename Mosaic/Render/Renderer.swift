//
//  Renderer.swift
//  Mosaic
//
//  MTKView delegate. Pulls the latest ARFrame each draw, encodes
//  the camera background pass, and presents the drawable. Future
//  passes (mesh overlay, post-fx) will slot into draw(in:) below
//  the camera pass.
//
//  Called on the main thread by MTKView, so all state is touched
//  from main with no locking.
//

import Foundation
import Metal
import MetalKit
import ARKit
import UIKit
import os

final class Renderer: NSObject, MTKViewDelegate {
    private let context = MetalContext.shared
    private let cameraBackgroundPass: CameraBackgroundPass

    weak var session: ARSession?

    private var viewportSize: CGSize = .zero

    init(view: MTKView, session: ARSession) {
        view.device = context.device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60

        self.cameraBackgroundPass = CameraBackgroundPass(
            context: context,
            colorPixelFormat: view.colorPixelFormat
        )
        self.session = session

        super.init()
        viewportSize = view.drawableSize
        view.delegate = self
        Log.metal.info("Renderer initialized · device=\(self.context.device.name, privacy: .public)")
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    // MARK: - Filter

    func setFilter(_ filter: CameraFilter) {
        cameraBackgroundPass.setFilter(filter)
    }

    func draw(in view: MTKView) {
        guard let frame = session?.currentFrame,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        commandBuffer.label = "MosaicFrame"
        encoder.label = "Mosaic.CameraEncoder"

        let orientation = currentInterfaceOrientation()
        cameraBackgroundPass.encode(
            into: encoder,
            frame: frame,
            viewportSize: viewportSize,
            orientation: orientation
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Helpers

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation ?? .portrait
    }
}
