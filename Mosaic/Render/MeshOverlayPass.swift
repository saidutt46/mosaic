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

/// Mesh-shader uniforms — must stay in lockstep with the
/// `MeshUniforms` struct in Shaders.metal. Tightly packed 4-byte
/// fields; 24 bytes total. Pushed to the fragment shader as a
/// single `setFragmentBytes` call at slot 2.
struct MeshUniforms {
    var alpha: Float
    var time: Float
    var fresnelIntensity: Float
    var scanLineIntensity: Float
    var densityStride: UInt32
    var classVisibilityMask: UInt32   // bit N ⇒ class N visible
    var visualizationMode: UInt32     // 0 = classification, 1 = density
    var densityLogMin: Float          // log2(area) mapped to ramp 0 (dense)
    var densityLogMax: Float          // log2(area) mapped to ramp 1 (sparse)
}

/// User-facing density preset. Raw value is the shader's
/// `densityStride` (1 = all triangles, 8 = sparse).
enum MeshDensity: UInt32, CaseIterable, Identifiable, Sendable {
    case full    = 1
    case half    = 2
    case quarter = 4
    case sparse  = 8

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .full:    "Full"
        case .half:    "Half"
        case .quarter: "Quarter"
        case .sparse:  "Sparse"
        }
    }

    /// Approximate percentage of triangles drawn at this stride.
    var percentLabel: String {
        switch self {
        case .full:    "100%"
        case .half:    "50%"
        case .quarter: "25%"
        case .sparse:  "12%"
        }
    }
}

final class MeshOverlayPass {

    enum FillMode: Sendable {
        case wireframe
        case filled
    }

    /// Default per-classification colour palette, indexed by
    /// `ARMeshClassification` raw value (0 none … 7 door). Mirrors
    /// `MosaicColor.Classification` — used as the starting point
    /// before XrayView injects the user's customised palette.
    static let defaultPalette: [SIMD4<Float>] = [
        SIMD4<Float>(0.56, 0.56, 0.58, 1.0), // 0 none      · gray
        SIMD4<Float>(0.35, 0.78, 0.98, 1.0), // 1 wall      · cyan
        SIMD4<Float>(0.20, 0.78, 0.35, 1.0), // 2 floor     · green
        SIMD4<Float>(0.69, 0.32, 0.87, 1.0), // 3 ceiling   · purple
        SIMD4<Float>(1.00, 0.58, 0.00, 1.0), // 4 table     · orange
        SIMD4<Float>(1.00, 0.80, 0.00, 1.0), // 5 seat      · yellow
        SIMD4<Float>(0.39, 0.82, 1.00, 1.0), // 6 window    · light blue
        SIMD4<Float>(1.00, 0.22, 0.37, 1.0), // 7 door      · pink
    ]

    /// All 8 classes visible — bits 0..7 set.
    static let defaultVisibilityMask: UInt32 = 0xFF

    private let context: MetalContext
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    var fillMode: FillMode = .wireframe
    var density: MeshDensity = .full
    var fresnelIntensity: Float = 0.0
    var opacity: Float = 0.55                       // 0…1 alpha multiplier
    var palette: [SIMD4<Float>] = defaultPalette
    var classVisibilityMask: UInt32 = defaultVisibilityMask
    var visualizationMode: MeshVisualizationMode = .classification

    /// Absolute log2(area m²) window for the `.quality` ramp — a fixed
    /// real-world bar (≈0.00024 m² dense … ≈0.0078 m² sparse). Well-
    /// sampled surfaces clear it (green); only genuinely sparse faces
    /// read red. `.density` ignores this and adapts to the live scene.
    private static let qualityLogBounds: (min: Float, max: Float) = (-12, -7)

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

        // Camera position in world space — used by the vertex
        // shader to compute per-vertex view direction for Fresnel.
        // ARCamera.transform is the camera-to-world transform, so
        // the translation column IS the camera's world position.
        let camCol = frame.camera.transform.columns.3
        var cameraWorldPos = SIMD3<Float>(camCol.x, camCol.y, camCol.z)

        encoder.pushDebugGroup("MeshOverlay")
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setTriangleFillMode(fillMode == .wireframe ? .lines : .fill)
        encoder.setCullMode(.none)  // mesh has no consistent winding

        // Per-frame vertex uniform — push once, persists across the
        // draw loop below.
        encoder.setVertexBytes(&cameraWorldPos,
                               length: MemoryLayout<SIMD3<Float>>.size,
                               index: 4)

        // User's per-class palette pushed once per frame at slot 1.
        var palette = self.palette
        encoder.setFragmentBytes(
            &palette,
            length: MemoryLayout<SIMD4<Float>>.size * palette.count,
            index: 1
        )

        // Area-ramp bounds depend on the mode: density adapts to the
        // live scene's p5/p95 face-area spread (relative); quality uses
        // a fixed real-world window (absolute). Classification ignores
        // these entirely.
        let densityBounds: (min: Float, max: Float)
        switch visualizationMode {
        case .density: densityBounds = cache.densityLogBounds
        case .quality, .classification: densityBounds = Self.qualityLogBounds
        }

        // Per-frame mesh-shader uniforms pushed as one struct at
        // fragment buffer slot 2. classVisibilityMask gates which
        // classes draw at all (see shader: discard_fragment).
        var uniforms = MeshUniforms(
            alpha: opacity,                 // user-driven; was fillMode-derived
            time: 0,                        // scan-line slot, no-op
            fresnelIntensity: fresnelIntensity,
            scanLineIntensity: 0,
            densityStride: density.rawValue,
            classVisibilityMask: classVisibilityMask,
            visualizationMode: visualizationMode.rawValue,
            densityLogMin: densityBounds.min,
            densityLogMax: densityBounds.max
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<MeshUniforms>.stride,
            index: 2
        )

        for buffers in snapshot {
            // Skip anchors that arrived without classifications or
            // normals — shouldn't happen under .meshWithClassification,
            // but defending here is cheaper than tracking down a
            // crash later.
            guard let classBuffer = buffers.classificationBuffer,
                  let normalBuffer = buffers.normalBuffer else {
                continue
            }

            var mvp = viewProjection * buffers.transform
            var model = buffers.transform

            encoder.setVertexBuffer(buffers.vertexBuffer,
                                    offset: 0, index: 0)
            encoder.setVertexBytes(&mvp,
                                   length: MemoryLayout<simd_float4x4>.size,
                                   index: 1)
            encoder.setVertexBuffer(normalBuffer, offset: 0, index: 2)
            encoder.setVertexBytes(&model,
                                   length: MemoryLayout<simd_float4x4>.size,
                                   index: 3)
            // cameraWorldPos at vertex slot 4 is set once outside
            // the loop — persists across draws.

            encoder.setFragmentBuffer(classBuffer, offset: 0, index: 0)
            if let areaBuffer = buffers.areaBuffer {
                encoder.setFragmentBuffer(areaBuffer, offset: 0, index: 3)
            }
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
