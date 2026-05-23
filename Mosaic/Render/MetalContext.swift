//
//  MetalContext.swift
//  Mosaic
//
//  Shared Metal device + command queue + default shader library.
//  One instance for the app — passed (or pulled from .shared) by
//  every render pass.
//
//  Mosaic targets LiDAR iPhones/iPads where Metal is guaranteed; if
//  any of these allocations fails the app cannot function, so we
//  fail fast with a clear message rather than papering over it.
//

import Metal

final class MetalContext {
    static let shared = MetalContext()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Mosaic requires Metal — no system default device.")
        }
        guard let queue = device.makeCommandQueue() else {
            fatalError("Mosaic requires Metal — failed to create command queue.")
        }
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Mosaic requires Metal — failed to load default shader library.")
        }
        self.device = device
        self.commandQueue = queue
        self.library = library
    }
}
