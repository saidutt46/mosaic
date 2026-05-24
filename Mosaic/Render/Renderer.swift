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
    private let meshOverlayPass: MeshOverlayPass

    weak var session: ARSession?
    weak var meshCache: MeshAnchorBufferCache?

    private var viewportSize: CGSize = .zero

    // MARK: Capture
    //
    // When `requestCapture` is called we set `captureCallback`. On
    // the next draw we blit the drawable's texture into our owned
    // `.shared` capture texture (CPU-readable), then on the GPU
    // completion handler convert that texture to a UIImage and hand
    // it back on the main queue. One-shot — cleared after firing.
    private var captureCallback: (@Sendable (UIImage?) -> Void)?
    private var captureTexture: MTLTexture?

    init(view: MTKView, session: ARSession, meshCache: MeshAnchorBufferCache) {
        view.device = context.device
        view.colorPixelFormat = .bgra8Unorm
        // Depth attachment so the mesh overlay pass can self-occlude.
        // Camera pass disables write/test on this attachment (see
        // CameraBackgroundPass) so it just paints colour.
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.clearDepth = 1.0
        // framebufferOnly must be false so capture can blit-copy the
        // drawable's texture into our CPU-readable capture texture.
        // Setting this to true (the default) makes drawable textures
        // unreadable and crashes Metal at blit time.
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60

        self.cameraBackgroundPass = CameraBackgroundPass(
            context: context,
            colorPixelFormat: view.colorPixelFormat,
            depthPixelFormat: view.depthStencilPixelFormat
        )
        self.meshOverlayPass = MeshOverlayPass(
            context: context,
            colorPixelFormat: view.colorPixelFormat,
            depthPixelFormat: view.depthStencilPixelFormat
        )
        self.session = session
        self.meshCache = meshCache

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

    // MARK: - Capture

    /// Schedule a one-shot snapshot of the currently rendered
    /// drawable. Completion fires on the main queue with the
    /// composited frame (camera + active filter), or nil on failure.
    func requestCapture(_ completion: @escaping @Sendable (UIImage?) -> Void) {
        captureCallback = completion
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

        if let meshCache {
            meshOverlayPass.encode(
                into: encoder,
                cache: meshCache,
                frame: frame,
                viewportSize: viewportSize,
                orientation: orientation
            )
        }

        encoder.endEncoding()

        // If a capture was requested, blit the drawable into our
        // CPU-readable texture and convert to UIImage on completion.
        if let callback = captureCallback {
            captureCallback = nil
            ensureCaptureTexture(matching: drawable.texture)
            if let captureTex = captureTexture,
               let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.label = "MosaicCapture"
                blit.copy(from: drawable.texture, to: captureTex)
                blit.endEncoding()
                commandBuffer.addCompletedHandler { _ in
                    let image = Self.makeUIImage(from: captureTex)
                    DispatchQueue.main.async { callback(image) }
                }
            } else {
                DispatchQueue.main.async { callback(nil) }
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func ensureCaptureTexture(matching source: MTLTexture) {
        if let tex = captureTexture,
           tex.width == source.width,
           tex.height == source.height,
           tex.pixelFormat == source.pixelFormat { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared  // CPU-readable
        descriptor.usage = [.shaderRead]
        captureTexture = context.device.makeTexture(descriptor: descriptor)
    }

    private static func makeUIImage(from texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let dataSize = bytesPerRow * height

        var bytes = [UInt8](repeating: 0, count: dataSize)
        bytes.withUnsafeMutableBufferPointer { buf in
            texture.getBytes(buf.baseAddress!,
                             bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, width, height),
                             mipmapLevel: 0)
        }

        // Drawable is .bgra8Unorm → swap byte order to little-endian
        // BGRA so CoreGraphics renders the channels in the right order.
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(bytes) as CFData

        guard let provider = CGDataProvider(data: data),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Helpers

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation ?? .portrait
    }
}
