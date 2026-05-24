//
//  MeshPreset.swift
//  Mosaic
//
//  A "vibe" — one-tap combination of every X-Ray mesh control:
//  fillMode, density, opacity, fresnel intensity, per-class color,
//  per-class visibility. Picking a preset hard-resets all of these
//  to that preset's values; the user can still tune individual
//  knobs afterwards in the classification sheet.
//

import SwiftUI
import ARKit

enum MeshPreset: String, CaseIterable, Identifiable {
    case mosaic     // app default — colourful classified mesh
    case cyber      // neon, filled, edge-glow
    case mono       // all-white sketch, bold wireframe
    case minimal    // muted, sparse, subtle
    case floorplan  // walls + floor only, top-down feel

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mosaic:    "Mosaic"
        case .cyber:     "Cyber"
        case .mono:      "Mono"
        case .minimal:   "Minimal"
        case .floorplan: "Floorplan"
        }
    }

    var caption: String {
        switch self {
        case .mosaic:    "Default classified colours"
        case .cyber:     "Neon palette with edge glow"
        case .mono:      "Stark white wireframe"
        case .minimal:   "Sparse, muted, ambient"
        case .floorplan: "Walls + floor only"
        }
    }

    // MARK: - Mesh-wide settings

    var fillMode: MeshOverlayPass.FillMode {
        switch self {
        case .mosaic:    .wireframe
        case .cyber:     .wireframe
        case .mono:      .wireframe
        case .minimal:   .wireframe
        case .floorplan: .filled
        }
    }

    var density: MeshDensity {
        switch self {
        case .mosaic:    .full
        case .cyber:     .full
        case .mono:      .full
        case .minimal:   .sparse
        case .floorplan: .full
        }
    }

    var opacity: Float {
        switch self {
        case .mosaic:    0.55
        case .cyber:     0.65
        case .mono:      1.00
        case .minimal:   0.40
        case .floorplan: 0.85
        }
    }

    var fresnelIntensity: Float {
        switch self {
        case .mosaic:    0.00
        case .cyber:     0.65
        case .mono:      0.00
        case .minimal:   0.25
        case .floorplan: 0.00
        }
    }

    // MARK: - Per-class settings

    /// Color + visibility per ARMeshClassification. Used by
    /// `apply(to:)` to overwrite the live ClassificationStyles.
    func config(for c: ARMeshClassification) -> (color: Color, visible: Bool) {
        switch self {
        case .mosaic:
            return (Self.mosaicColor(for: c), true)
        case .cyber:
            return (Self.cyberColor(for: c), true)
        case .mono:
            return (Self.monoColor(for: c), true)
        case .minimal:
            return (Self.minimalColor(for: c), true)
        case .floorplan:
            let visible: Bool = (c == .wall || c == .floor || c == .none)
            return (Self.floorplanColor(for: c), visible)
        }
    }

    /// Hero-card preview swatches (4 representative colours):
    /// wall · floor · ceiling · seat. Same order across all
    /// presets so visually they read as comparable.
    var previewColors: [Color] {
        [.wall, .floor, .ceiling, .seat].map { config(for: $0).color }
    }

    // MARK: - Apply

    @MainActor
    func apply(to styles: ClassificationStyles) {
        for i in styles.entries.indices {
            let c = styles.entries[i].classification
            let cfg = config(for: c)
            styles.entries[i].color = cfg.color
            styles.entries[i].isVisible = cfg.visible
        }
    }

    // MARK: - Per-preset palettes

    private static func mosaicColor(for c: ARMeshClassification) -> Color {
        switch c {
        case .none:    MosaicColor.Classification.unclassified
        case .wall:    MosaicColor.Classification.wall
        case .floor:   MosaicColor.Classification.floor
        case .ceiling: MosaicColor.Classification.ceiling
        case .table:   MosaicColor.Classification.table
        case .seat:    MosaicColor.Classification.seat
        case .window:  MosaicColor.Classification.window
        case .door:    MosaicColor.Classification.door
        @unknown default: .gray
        }
    }

    /// Cyber — neon-noir. Hot pink walls, electric cyan floor.
    private static func cyberColor(for c: ARMeshClassification) -> Color {
        switch c {
        case .none:    Color(hex: 0x2A2A2A)
        case .wall:    Color(hex: 0xFF2D95)   // hot pink
        case .floor:   Color(hex: 0x00E5FF)   // electric cyan
        case .ceiling: Color(hex: 0x7C3AED)   // violet
        case .table:   Color(hex: 0xFFD600)   // yellow
        case .seat:    Color(hex: 0x00FF88)   // neon green
        case .window:  Color(hex: 0x18FFFF)   // bright cyan
        case .door:    Color(hex: 0xFF5722)   // orange-red
        @unknown default: .gray
        }
    }

    /// Mono — all whites/light grays. Stark architectural sketch.
    private static func monoColor(for c: ARMeshClassification) -> Color {
        switch c {
        case .none:    Color(hex: 0x999999)
        case .wall:    Color(hex: 0xFFFFFF)
        case .floor:   Color(hex: 0xE0E0E0)
        case .ceiling: Color(hex: 0xFFFFFF)
        case .table:   Color(hex: 0xCCCCCC)
        case .seat:    Color(hex: 0xCCCCCC)
        case .window:  Color(hex: 0xFFFFFF)
        case .door:    Color(hex: 0xCCCCCC)
        @unknown default: .white
        }
    }

    /// Minimal — defaults dimmed; visible but unassertive.
    private static func minimalColor(for c: ARMeshClassification) -> Color {
        switch c {
        case .none:    Color(hex: 0x9E9E9E)
        case .wall:    Color(hex: 0x90D5F0)
        case .floor:   Color(hex: 0xA8D8AA)
        case .ceiling: Color(hex: 0xC8AEDB)
        case .table:   Color(hex: 0xF0C080)
        case .seat:    Color(hex: 0xF0DC80)
        case .window:  Color(hex: 0xB0DBFF)
        case .door:    Color(hex: 0xF09BA8)
        @unknown default: .gray
        }
    }

    /// Floorplan — only walls + floor pop. Top-down architectural.
    private static func floorplanColor(for c: ARMeshClassification) -> Color {
        switch c {
        case .none:    Color(hex: 0x666666)
        case .wall:    Color(hex: 0xFFFFFF)
        case .floor:   Color(hex: 0xB8E6B8)   // pale green
        case .ceiling: Color(hex: 0x444444)
        case .table:   Color(hex: 0x666666)
        case .seat:    Color(hex: 0x666666)
        case .window:  Color(hex: 0xAACCFF)
        case .door:    Color(hex: 0x888888)
        @unknown default: .gray
        }
    }
}
