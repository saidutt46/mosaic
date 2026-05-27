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
//  coverage   — accumulated LiDAR observation quality (confidence ×
//     proximity) per region of space, looked up per face from the
//     world-space CoverageGrid. The "how well-scanned is this?" signal.
//  Raw value is the shader's `visualizationMode` uniform.
//

import Foundation

enum MeshVisualizationMode: UInt32, CaseIterable, Identifiable, Sendable {
    case classification = 0
    case density = 1
    case quality = 2
    case coverage = 3

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .classification: "Classification"
        case .density:        "Density"
        case .quality:        "Quality"
        case .coverage:       "Coverage"
        }
    }

    /// One-line gloss for the mode-picker menu.
    var menuDetail: String {
        switch self {
        case .classification: "Colour by surface class"
        case .density:        "Relative triangle size in view"
        case .quality:        "Well-sampled vs sparse surfaces"
        case .coverage:       "Scan completeness (confidence)"
        }
    }

    var icon: String {
        switch self {
        case .classification: "paintpalette"
        case .density:        "point.3.connected.trianglepath.dotted"
        case .quality:        "checkmark.seal"
        case .coverage:       "viewfinder"
        }
    }

    /// Whether the shader colours faces by the triangle-area ramp
    /// (density/quality) — coverage and classification do not.
    var usesAreaRamp: Bool { self == .density || self == .quality }
}
