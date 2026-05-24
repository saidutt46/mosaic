//
//  ClassificationStyles.swift
//  Mosaic
//
//  XrayView's per-class render configuration. One Entry per
//  ARMeshClassification (color + visibility). Owned as @State by
//  XrayView; lives for the lifetime of one X-Ray session.
//
//  Exposes the GPU-ready palette (`[SIMD4<Float>]` of 8 colors)
//  and visibility bitmask (`UInt32`, bit N set ⇒ class N visible)
//  that MeshOverlayPass consumes each frame.
//

import SwiftUI
import ARKit
import Observation

@MainActor
@Observable
final class ClassificationStyles {

    struct Entry: Identifiable, Equatable {
        var classification: ARMeshClassification
        var color: Color
        var isVisible: Bool

        var id: Int { Int(classification.rawValue) }
    }

    /// Ordered by ARMeshClassification raw value (0 none … 7 door).
    var entries: [Entry]

    init() {
        self.entries = Self.makeDefaults()
    }

    func reset() {
        self.entries = Self.makeDefaults()
    }

    // MARK: - GPU-ready snapshots

    /// 8 entries indexed by ARMeshClassification raw value. Used by
    /// MeshOverlayPass as the palette uniform.
    var palette: [SIMD4<Float>] {
        var arr = Array(repeating: SIMD4<Float>(0, 0, 0, 1), count: 8)
        for entry in entries {
            arr[Int(entry.classification.rawValue)] = entry.color.simd4
        }
        return arr
    }

    /// Bit N is set when class with raw value N is visible.
    var visibilityMask: UInt32 {
        var mask: UInt32 = 0
        for entry in entries where entry.isVisible {
            mask |= 1 << UInt32(entry.classification.rawValue)
        }
        return mask
    }

    // MARK: - Defaults

    private static func makeDefaults() -> [Entry] {
        ARMeshClassification.allKnown.map { c in
            Entry(classification: c,
                  color: Self.defaultColor(for: c),
                  isVisible: true)
        }
    }

    /// Mirrors `MosaicColor.Classification` — keep in sync.
    private static func defaultColor(for c: ARMeshClassification) -> Color {
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
}

// MARK: - Color → SIMD4<Float>

extension Color {
    /// Pre-multiplied linear RGBA as expected by the mesh fragment.
    /// Uses UIColor to extract components — the SwiftUI Color API
    /// doesn't expose them directly.
    var simd4: SIMD4<Float> {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}
