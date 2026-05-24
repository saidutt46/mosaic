//
//  CameraBackgroundPass.swift
//  Mosaic
//
//  Renders ARKit's live camera feed as the scene background. The
//  pixel buffer arrives bi-planar YCbCr; we convert each plane to
//  a MTLTexture via CVMetalTextureCache (zero-copy) and let the
//  fragment shader do YCbCr→RGB.
//
//  Supports a swappable fragment shader per CameraFilter. Pipeline
//  states are built lazily on first request and cached, so changing
//  filters at runtime costs nothing after the first switch.
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
    private let colorPixelFormat: MTLPixelFormat
    private let depthPixelFormat: MTLPixelFormat
    private let vertexFunction: MTLFunction
    private let textureCache: CVMetalTextureCache
    private let depthState: MTLDepthStencilState

    /// Cached pipeline state per filter. Built on demand.
    private var pipelineStates: [CameraFilter: MTLRenderPipelineState] = [:]

    private(set) var currentFilter: CameraFilter = .none

    // Hold references across the draw boundary so the underlying
    // CVPixelBuffer isn't recycled while the GPU is still sampling.
    private var lumaTexture: CVMetalTexture?
    private var chromaTexture: CVMetalTexture?

    init(context: MetalContext,
         colorPixelFormat: MTLPixelFormat,
         depthPixelFormat: MTLPixelFormat) {
        self.context = context
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat

        guard let vertexFn = context.library.makeFunction(name: "cameraVertex") else {
            fatalError("CameraBackgroundPass: missing cameraVertex function.")
        }
        self.vertexFunction = vertexFn

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, context.device, nil, &cache
        )
        guard status == kCVReturnSuccess, let cache else {
            fatalError("CameraBackgroundPass: CVMetalTextureCache creation failed (\(status)).")
        }
        self.textureCache = cache

        // Camera always passes the depth test and never writes to
        // depth — it's a background fill. The mesh overlay pass
        // (B.2+) writes/tests against itself on the same attachment.
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.label = "CameraBackground.Depth"
        depthDesc.depthCompareFunction = .always
        depthDesc.isDepthWriteEnabled = false
        guard let depthState = context.device.makeDepthStencilState(descriptor: depthDesc) else {
            fatalError("CameraBackgroundPass: depth-stencil state creation failed.")
        }
        self.depthState = depthState

        // Pre-build the pass-through pipeline so we always have a
        // valid fallback when a filter's fragment can't be loaded.
        guard pipelineState(for: .none) != nil else {
            fatalError("CameraBackgroundPass: failed to build pass-through pipeline.")
        }
    }

    // MARK: - Filter control

    func setFilter(_ filter: CameraFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        // Warm the cache so the first draw with the new filter
        // doesn't stall on pipeline creation.
        _ = pipelineState(for: filter)
        Log.metal.info("filter → \(filter.rawValue, privacy: .public)")
    }

    // MARK: - Draw

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

        // ARFrame.displayTransform maps IMAGE UV → VIEWPORT UV. In the
        // vertex shader we go the other way (we know the viewport
        // vertex, we want to know which image UV to sample), so we
        // pass the INVERSE. Without this the image is rotated wrong
        // and the unmapped strips at top/bottom sample garbage.
        let dt = frame.displayTransform(
            for: orientation, viewportSize: viewportSize
        ).inverted()
        var transform = simd_float3x3(
            SIMD3<Float>(Float(dt.a),  Float(dt.b),  0),
            SIMD3<Float>(Float(dt.c),  Float(dt.d),  0),
            SIMD3<Float>(Float(dt.tx), Float(dt.ty), 1)
        )

        let pipeline = pipelineState(for: currentFilter) ?? pipelineStates[.none]!
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBytes(&transform,
                               length: MemoryLayout<simd_float3x3>.size,
                               index: 0)
        encoder.setFragmentTexture(lumaMTL, index: 0)
        encoder.setFragmentTexture(chromaMTL, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    // MARK: - Pipeline cache

    private func pipelineState(for filter: CameraFilter) -> MTLRenderPipelineState? {
        if let cached = pipelineStates[filter] { return cached }

        guard let fragmentFn = context.library.makeFunction(name: filter.fragmentFunctionName) else {
            Log.metal.warning("filter \(filter.rawValue, privacy: .public) — fragment '\(filter.fragmentFunctionName, privacy: .public)' not found; using pass-through")
            return pipelineStates[.none]
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Camera.\(filter.rawValue)"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat

        do {
            let state = try context.device
                .makeRenderPipelineState(descriptor: descriptor)
            pipelineStates[filter] = state
            return state
        } catch {
            Log.metal.error("filter \(filter.rawValue, privacy: .public) pipeline failed: \(error.localizedDescription, privacy: .public)")
            return pipelineStates[.none]
        }
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
