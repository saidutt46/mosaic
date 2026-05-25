//
//  CameraPreset.swift
//  Mosaic
//
//  Named camera angles for the scan detail viewer. Each preset is a
//  (elevation, azimuth) pair in radians, applied as a spherical orbit
//  around the model's centre (see RealityModelView). Default is an
//  isometric 3/4 view.
//

import Foundation
import simd

enum CameraPreset: String, CaseIterable, Identifiable, Sendable {
    case isometricRight
    case isometricLeft
    case top
    case front
    case back
    case left
    case right

    static let `default`: CameraPreset = .isometricRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .isometricRight: "Iso R"
        case .isometricLeft:  "Iso L"
        case .top:            "Top"
        case .front:          "Front"
        case .back:           "Back"
        case .left:           "Left"
        case .right:          "Right"
        }
    }

    var icon: String {
        switch self {
        case .isometricRight, .isometricLeft: "view.3d"
        case .top:   "arrow.down.to.line"
        case .front: "arrow.backward.to.line"
        case .back:  "arrow.forward.to.line"
        case .left:  "arrow.left.to.line"
        case .right: "arrow.right.to.line"
        }
    }

    /// (elevation, azimuth) in radians. elevation 0 = straight down the
    /// Y axis; azimuth orbits around it.
    var rotation: SIMD2<Float> {
        switch self {
        case .isometricRight: SIMD2(0.75,  .pi / 4)
        case .isometricLeft:  SIMD2(0.75, -.pi / 4)
        case .top:            SIMD2(0.05,  0)
        case .front:          SIMD2(.pi / 2, 0)
        case .back:           SIMD2(.pi / 2, .pi)
        case .left:           SIMD2(.pi / 2, -.pi / 2)
        case .right:          SIMD2(.pi / 2,  .pi / 2)
        }
    }
}
