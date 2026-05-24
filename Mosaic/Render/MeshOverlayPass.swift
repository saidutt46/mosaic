//
//  MeshOverlayPass.swift
//  Mosaic
//
//  Renders the classified ARKit mesh on top of the camera feed.
//  Reads from MeshAnchorBufferCache (one snapshot per frame) and
//  issues a single indexed-triangle draw call per cached anchor.
//
//  B.2 — Wireframe in a flat colour. Validates the matrix pipeline
//  (anchor-local → world → view → clip) and depth setup. Per-class
//  colouring comes in B.3.
//

import Foundation
import Metal
import ARKit
import simd
import UIKit
import os

final class MeshOverlayPass {

    enum FillMode: Sendable {
        case wireframe
        case filled
    }

    /// Per-classification colour palette indexed by
    /// `ARMeshClassification` raw value (0 none … 7 door). Mirrors
    /// `MosaicColor.Classification` — keep them in sync.
    /// Stored as SIMD4<Float> so it pushes straight to the GPU as
    /// a constant buffer.
    private static let classificationPalette: [SIMD4<Float>] = [
        SIMD4<Float>(0.56, 0.56, 0.58, 1.0), // 0 none      · gray
        SIMD4<Float>(0.35, 0.78, 0.98, 1.0), // 1 wall      · cyan
        SIMD4<Float>(0.20, 0.78, 0.35, 1.0), // 2 floor     · green
        SIMD4<Float>(0.69, 0.32, 0.87, 1.0), // 3 ceiling   · purple
        SIMD4<Float>(1.00, 0.58, 0.00, 1.0), // 4 table     · orange
        SIMD4<Float>(1.00, 0.80, 0.00, 1.0), // 5 seat      · yellow
        SIMD4<Float>(0.39, 0.82, 1.00, 1.0), // 6 window    · light blue
        SIMD4<Float>(1.00, 0.22, 0.37, 1.0), // 7 door      · pink
    ]

    private let context: MetalContext
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    var fillMode: FillMode = .filled

    /// Per-fillMode alpha pushed to the fragment shader. Wireframe
    /// needs full opacity (thin lines vanish at low alpha); filled
    /// wants translucency so the camera shows through the X-ray.
    private static func alpha(for fillMode: FillMode) -> Float {
        switch fillMode {
        case .wireframe: 1.0
        case .filled:    0.55
        }
    }

    init(context: MetalContext,
         colorPixelFormat: MTLPixelFormat,
         depthPixelFormat: MTLPixelFormat) {
        self.context = context

        guard let vertexFn = context.library.makeFunction(name: "meshVertex"),
              let fragmentFn = context.library.makeFunction(name: "meshFragment") else {
            fatalError("MeshOverlayPass: missing mesh shader functions.")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "MeshOverlayPass"
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat

        // Alpha blend the mesh over the camera background using
        // straight (non-premultiplied) alpha. fillMode controls how
        // translucent the mesh ends up via a fragment-side alpha
        // multiplier.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipelineState = try context.device
                .makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("MeshOverlayPass: pipeline creation failed: \(error)")
        }

        // Mesh writes depth and tests against itself so triangles
        // behind closer ones get correctly hidden.
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.label = "MeshOverlay.Depth"
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        guard let depthState = context.device.makeDepthStencilState(descriptor: depthDesc) else {
            fatalError("MeshOverlayPass: depth-stencil state creation failed.")
        }
        self.depthState = depthState
    }

    /// Encode one indexed-triangle draw per cached mesh anchor.
    /// Caller has already set up the render encoder + camera
    /// background pass; this pass layers on top.
    func encode(into encoder: MTLRenderCommandEncoder,
                cache: MeshAnchorBufferCache,
                frame: ARFrame,
                viewportSize: CGSize,
                orientation: UIInterfaceOrientation) {

        let snapshot = cache.snapshot
        guard !snapshot.isEmpty else { return }

        // ARKit gives us a view+projection pair tuned to the
        // current orientation and viewport — exactly what we need
        // to draw into MTKView's clip space.
        let viewMatrix = frame.camera.viewMatrix(for: orientation)
        let projectionMatrix = frame.camera.projectionMatrix(
            for: orientation,
            viewportSize: viewportSize,
            zNear: 0.001,
            zFar: 50.0
        )
        let viewProjection = projectionMatrix * viewMatrix

        encoder.pushDebugGroup("MeshOverlay")
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setTriangleFillMode(fillMode == .wireframe ? .lines : .fill)
        encoder.setCullMode(.none)  // mesh has no consistent winding

        // Palette is constant across all anchors — push once per
        // frame as fragment buffer slot 1.
        var palette = Self.classificationPalette
        encoder.setFragmentBytes(
            &palette,
            length: MemoryLayout<SIMD4<Float>>.size * palette.count,
            index: 1
        )

        // Alpha derives from the current fillMode (wireframe opaque,
        // filled translucent). Pushed as fragment buffer slot 2.
        var alpha: Float = Self.alpha(for: fillMode)
        encoder.setFragmentBytes(
            &alpha,
            length: MemoryLayout<Float>.size,
            index: 2
        )

        for buffers in snapshot {
            // Skip anchors that arrived without classifications —
            // shouldn't happen under .meshWithClassification, but
            // defending against the fragment indexing into nothing
            // is cheaper than tracking down a crash later.
            guard let classBuffer = buffers.classificationBuffer else {
                continue
            }

            var mvp = viewProjection * buffers.transform

            encoder.setVertexBuffer(buffers.vertexBuffer,
                                    offset: 0, index: 0)
            encoder.setVertexBytes(&mvp,
                                   length: MemoryLayout<simd_float4x4>.size,
                                   index: 1)
            encoder.setFragmentBuffer(classBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: buffers.faceCount * 3,
                indexType: .uint32,
                indexBuffer: buffers.indexBuffer,
                indexBufferOffset: 0
            )
        }

        encoder.popDebugGroup()
    }
}
