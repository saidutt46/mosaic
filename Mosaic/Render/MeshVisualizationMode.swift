//
//  MeshVisualizationMode.swift
//  Mosaic
//
//  How the mesh overlay colours its faces. Classification (per-class
//  palette) is the default; Density colours by triangle area as a
//  scan-quality proxy (small faces ≈ dense ≈ well-scanned). Raw value
//  is the shader's `visualizationMode` uniform. First entry of a
//  growing "render modes" framework (coverage/quality come later).
//

import Foundation

enum MeshVisualizationMode: UInt32, CaseIterable, Identifiable, Sendable {
    case classification = 0
    case density = 1

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .classification: "Classification"
        case .density:        "Density"
        }
    }

    var icon: String {
        switch self {
        case .classification: "paintpalette"
        case .density:        "grid"
        }
    }
}
