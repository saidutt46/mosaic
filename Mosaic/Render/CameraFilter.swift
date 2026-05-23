//
//  CameraFilter.swift
//  Mosaic
//
//  Catalog of camera-feed effects exposed in the filter strip.
//  Each case maps to a fragment-shader function in Shaders.metal.
//
//  `isImplemented` gates the UI — the chip is shown but disabled
//  until the matching Metal fragment lands. This lets us prototype
//  the strip with all 10 slots visible while wiring shaders one
//  at a time (Track A learning).
//

import Foundation

enum CameraFilter: String, CaseIterable, Identifiable, Sendable {
    case none
    case tint
    case monochrome
    case colorSwap
    case posterize
    case hueRotate
    case vignette
    case pixelate
    case edgeDetect
    case thermal

    var id: String { rawValue }

    /// Display label shown beneath the icon in the strip.
    var label: String {
        switch self {
        case .none:       "Original"
        case .tint:       "Tint"
        case .monochrome: "B&W"
        case .colorSwap:  "Swap"
        case .posterize:  "Poster"
        case .hueRotate:  "Hue"
        case .vignette:   "Vignette"
        case .pixelate:   "Pixel"
        case .edgeDetect: "Edge"
        case .thermal:    "Thermal"
        }
    }

    /// SF Symbol drawn in the chip.
    var icon: String {
        switch self {
        case .none:       "circle.dashed"
        case .tint:       "paintpalette.fill"
        case .monochrome: "circle.lefthalf.filled"
        case .colorSwap:  "arrow.left.arrow.right"
        case .posterize:  "square.stack.3d.up.fill"
        case .hueRotate:  "rotate.3d"
        case .vignette:   "circle.dotted"
        case .pixelate:   "square.grid.3x3.fill"
        case .edgeDetect: "scribble.variable"
        case .thermal:    "thermometer.medium"
        }
    }

    /// Metal fragment function name. `.none` is the pass-through
    /// shader we already had.
    var fragmentFunctionName: String {
        switch self {
        case .none:       "cameraFragment"
        case .tint:       "cameraFragmentTint"
        case .monochrome: "cameraFragmentMonochrome"
        case .colorSwap:  "cameraFragmentColorSwap"
        case .posterize:  "cameraFragmentPosterize"
        case .hueRotate:  "cameraFragmentHueRotate"
        case .vignette:   "cameraFragmentVignette"
        case .pixelate:   "cameraFragmentPixelate"
        case .edgeDetect: "cameraFragmentEdge"
        case .thermal:    "cameraFragmentThermal"
        }
    }

    /// True once the Metal fragment for this case is implemented.
    /// Flip to true as each shader lands; the strip chip enables.
    var isImplemented: Bool {
        switch self {
        case .none, .tint, .monochrome, .colorSwap, .posterize, .hueRotate: true
        default:                                                            false
        }
    }
}
