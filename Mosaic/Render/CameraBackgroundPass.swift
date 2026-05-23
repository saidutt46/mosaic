//
//  CameraBackgroundPass.swift
//  Mosaic
//
//  Renders ARKit's live camera feed as the scene background. The
//  pixel buffer arrives bi-planar YCbCr; we convert each plane to
//  a MTLTexture via CVMetalTextureCache (zero-copy) and let the
//  fragment shader do YCbCr→RGB.
//

import Foundation
import Metal
import ARKit
import CoreVideo
import simd
import UIKit
import os

final class CameraBackgroundPass {
    private let context: MetalContext
    private let pipelineState: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache

    // Hold references across the draw boundary so the underlying
    // CVPixelBuffer isn't recycled while the GPU is still sampling.
    private var lumaTexture: CVMetalTexture?
    private var chromaTexture: CVMetalTexture?

    init(context: MetalContext, colorPixelFormat: MTLPixelFormat) {
        self.context = context

        guard let vertexFn = context.library.makeFunction(name: "cameraVertex"),
              let fragmentFn = context.library.makeFunction(name: "cameraFragment") else {
            fatalError("CameraBackgroundPass: missing shader functions in default library.")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "CameraBackgroundPass"
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            self.pipelineState = try context.device
                .makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("CameraBackgroundPass: pipeline creation failed: \(error)")
        }

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, context.device, nil, &cache
        )
        guard status == kCVReturnSuccess, let cache else {
            fatalError("CameraBackgroundPass: CVMetalTextureCache creation failed (\(status)).")
        }
        self.textureCache = cache
    }

    /// Encode the camera quad into the given render encoder.
    /// Returns `false` if the frame's pixel buffer couldn't be used
    /// (caller should leave the previous drawable in place).
    @discardableResult
    func encode(into encoder: MTLRenderCommandEncoder,
                frame: ARFrame,
                viewportSize: CGSize,
                orientation: UIInterfaceOrientation) -> Bool {
        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            Log.metal.warning("camera pixel buffer has fewer than 2 planes")
            return false
        }

        guard let luma = makeTexture(from: pixelBuffer, planeIndex: 0, format: .r8Unorm),
              let chroma = makeTexture(from: pixelBuffer, planeIndex: 1, format: .rg8Unorm),
              let lumaMTL = CVMetalTextureGetTexture(luma),
              let chromaMTL = CVMetalTextureGetTexture(chroma) else {
            return false
        }
        self.lumaTexture = luma
        self.chromaTexture = chroma

        // ARFrame.displayTransform returns a CGAffineTransform that
        // maps UV (image-space) to view-space for the given
        // orientation + size. We hoist it into a column-major float3x3
        // so the vertex shader can apply it directly.
        let dt = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        var transform = simd_float3x3(
            SIMD3<Float>(Float(dt.a),  Float(dt.b),  0),
            SIMD3<Float>(Float(dt.c),  Float(dt.d),  0),
            SIMD3<Float>(Float(dt.tx), Float(dt.ty), 1)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&transform,
                               length: MemoryLayout<simd_float3x3>.size,
                               index: 0)
        encoder.setFragmentTexture(lumaMTL, index: 0)
        encoder.setFragmentTexture(chromaMTL, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    // MARK: - Helpers

    private func makeTexture(from buffer: CVPixelBuffer,
                             planeIndex: Int,
                             format: MTLPixelFormat) -> CVMetalTexture? {
        let width  = CVPixelBufferGetWidthOfPlane(buffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(buffer, planeIndex)
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil,
            format, width, height, planeIndex, &texture
        )
        guard status == kCVReturnSuccess else {
            Log.metal.warning("CVMetalTextureCache failed for plane \(planeIndex) status=\(status)")
            return nil
        }
        return texture
    }
}
