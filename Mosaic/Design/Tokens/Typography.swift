//
//  Typography.swift
//  Mosaic
//
//  SF Pro for content (Dynamic Type aware) + SF Mono for HUD/telemetry
//  readouts (fixed size — intentional, instrumentation should not scale).
//

import SwiftUI

enum MosaicFont {
    // MARK: Content — scales with Dynamic Type
    static let display  = Font.system(.largeTitle, design: .default, weight: .bold)
    static let title    = Font.system(.title,      design: .default, weight: .semibold)
    static let title2   = Font.system(.title2,     design: .default, weight: .semibold)
    static let headline = Font.system(.headline,   design: .default)
    static let body     = Font.system(.body,       design: .default)
    static let callout  = Font.system(.callout,    design: .default)
    static let footnote = Font.system(.footnote,   design: .default)
    static let caption  = Font.system(.caption,    design: .default)

    // MARK: Telemetry — fixed size monospace
    static let monoCaption = Font.system(size: 12, weight: .medium,   design: .monospaced)
    static let monoBody    = Font.system(size: 15, weight: .regular,  design: .monospaced)
    static let monoFigure  = Font.system(size: 28, weight: .semibold, design: .monospaced)
}
