//
//  Colors.swift
//  Mosaic
//
//  Color tokens — semantic chrome (defers to iOS system colors)
//  plus the ARKit classification palette that defines the product look.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum MosaicColor {
    // MARK: Chrome — adapts to light/dark via system semantics
    static let background        = Color(UIColor.systemBackground)
    static let surface           = Color(UIColor.secondarySystemBackground)
    static let groupedBackground = Color(UIColor.systemGroupedBackground)
    static let separator         = Color(UIColor.separator)

    // MARK: Brand
    static let accent = Color.accentColor
    static let hudCyan = Color(hex: 0x5AC8FA)
    static let hudMagenta = Color(hex: 0xFF375F)

    // MARK: Surface treatments
    static let hairline = Color.white.opacity(0.08)
    static let scrim = Color.black.opacity(0.5)

    // MARK: ARKit classification palette
    // Mapped to the 8 ARMeshClassification cases. These colors carry
    // semantic meaning and are reused by the Metal mesh overlay
    // and the UI swatches/legends — keep them in sync.
    enum Classification {
        static let unclassified = Color(hex: 0x8E8E93) // system gray
        static let wall         = Color(hex: 0x5AC8FA) // cyan
        static let floor        = Color(hex: 0x34C759) // green
        static let ceiling      = Color(hex: 0xAF52DE) // purple
        static let table        = Color(hex: 0xFF9500) // orange
        static let seat         = Color(hex: 0xFFCC00) // yellow
        static let window       = Color(hex: 0x64D2FF) // light blue
        static let door         = Color(hex: 0xFF375F) // pink

        static let all: [(name: String, color: Color)] = [
            ("none", unclassified), ("wall", wall), ("floor", floor), ("ceiling", ceiling),
            ("table", table), ("seat", seat), ("window", window), ("door", door),
        ]
    }
}
