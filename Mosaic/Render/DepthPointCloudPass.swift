//
//  DepthPointCloudPass.swift
//  Mosaic
//
//  F.2.1b — renders the CoverageGrid as world-space points coloured by
//  accumulated coverage quality (red = poorly observed → green = well
//  observed). Points persist in world space across frames, so they stick
//  to real surfaces as the camera moves — the proof that the depth→world
//  projection is correct, and the debug face of the coverage grid before
//  it drives the .coverage mesh mode (F.2.2).
//
//  The pass owns only the GPU point buffer; accumulation lives in
//  CoverageGrid. It rebuilds the buffer only when the grid's version
//  changes.
//

import Foundation
import Metal
import ARKit
import simd
import UIKit
import os

final class DepthPointCloudPass {

    private let context: MetalContext
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    /// One `SIMD4<Float>` per point: xyz = world position, w = quality.
    private var pointsBuffer: MTLBuffer?
    private var pointCapacity = 0
    private var pointCount = 0
    private var syncedVersion = -1

    init(context: MetalContext,
         colorPixelFormat: MTLPixelFormat,
         depthPixelFormat: MTLPixelFormat) {
        self.context = context

        guard let vertexFn = context.library.makeFunction(name: "depthPointVertex"),
              let fragmentFn = context.library.makeFunction(name: "depthPointFragment") else {
            fatalError("DepthPointCloudPass: missing point shader functions.")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DepthPointCloudPass"
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat

        do {
            self.pipelineState = try context.device
                .makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("DepthPointCloudPass: pipeline creation failed: \(error)")
        }

        // Debug overlay: always visible, no depth write (don't disturb
        // the mesh pass's depth buffer).
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.label = "DepthPointCloud.Depth"
        depthDesc.depthCompareFunction = .always
        depthDesc.isDepthWriteEnabled = false
        guard let depthState = context.device.makeDepthStencilState(descriptor: depthDesc) else {
            fatalError("DepthPointCloudPass: depth-stencil state creation failed.")
        }
        self.depthState = depthState
    }

    func encode(into encoder: MTLRenderCommandEncoder,
                grid: CoverageGrid,
                frame: ARFrame,
                viewportSize: CGSize,
                orientation: UIInterfaceOrientation) {

        sync(from: grid)
        guard pointCount > 0, let pointsBuffer else { return }

        var viewProjection = frame.camera.projectionMatrix(
            for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 50.0
        ) * frame.camera.viewMatrix(for: orientation)

        encoder.pushDebugGroup("CoveragePointCloud")
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(pointsBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&viewProjection,
                               length: MemoryLayout<simd_float4x4>.size,
                               index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)
        encoder.popDebugGroup()
    }

    /// Rebuild the GPU point buffer from the grid when it has changed.
    private func sync(from grid: CoverageGrid) {
        guard grid.version != syncedVersion else { return }
        syncedVersion = grid.version

        let needed = grid.occupiedCount
        guard needed > 0 else { pointCount = 0; return }
        ensureCapacity(needed)
        guard let pointsBuffer else { pointCount = 0; return }

        let pointer = pointsBuffer.contents().assumingMemoryBound(to: SIMD4<Float>.self)
        pointCount = grid.writePoints(into: pointer, capacity: pointCapacity)
    }

    private func ensureCapacity(_ capacity: Int) {
        guard pointsBuffer == nil || pointCapacity < capacity else { return }
        // Grow with headroom so we're not reallocating every frame as the
        // scan fills in.
        let target = max(capacity, pointCapacity * 2)
        pointsBuffer = context.device.makeBuffer(
            length: target * MemoryLayout<SIMD4<Float>>.size,
            options: .storageModeShared
        )
        pointsBuffer?.label = "Mosaic.CoveragePoints"
        pointCapacity = target
    }
}
