//
//  MeshVisualizationMode.swift
//  Mosaic
//
//  How the mesh overlay colours its faces. All modes share the same
//  per-face triangle-area ramp except `classification` (per-class
//  palette). The two area modes differ only in how the ramp is
//  normalised:
//   • density  — adaptive (this scene's p5/p95 face-area spread); a
//     RELATIVE reading: shows where triangles are big vs small *here*.
//   • quality  — absolute (a fixed real-world face-area window); an
//     ABSOLUTE reading: well-sampled surfaces read green, genuinely
//     sparse ones red, regardless of room.
//  Raw value is the shader's `visualizationMode` uniform. The next mode
//  (F.2) will be confidence-based Coverage, slotting in at raw 3.
//

import Foundation

enum MeshVisualizationMode: UInt32, CaseIterable, Identifiable, Sendable {
    case classification = 0
    case density = 1
    case quality = 2

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .classification: "Classification"
        case .density:        "Density"
        case .quality:        "Quality"
        }
    }

    /// One-line gloss for the mode-picker menu.
    var menuDetail: String {
        switch self {
        case .classification: "Colour by surface class"
        case .density:        "Relative triangle size in view"
        case .quality:        "Well-sampled vs sparse surfaces"
        }
    }

    var icon: String {
        switch self {
        case .classification: "paintpalette"
        case .density:        "point.3.connected.trianglepath.dotted"
        case .quality:        "checkmark.seal"
        }
    }

    /// Whether the shader colours faces by the triangle-area ramp
    /// (vs the per-class palette).
    var usesAreaRamp: Bool { self != .classification }
}
