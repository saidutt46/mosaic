//
//  GlassCard.swift
//  Mosaic
//
//  Liquid-glass surface for floating overlays — settings panels,
//  HUD readouts, palette pickers. Backed by .ultraThinMaterial for
//  broad compatibility; can be swapped to iOS 26 `.glassEffect()`
//  later if we want the native Liquid Glass treatment specifically.
//

import SwiftUI

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = MosaicRadius.lg
    var padding: CGFloat = MosaicSpacing.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(MosaicColor.hairline, lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(
        radius: CGFloat = MosaicRadius.lg,
        padding: CGFloat = MosaicSpacing.cardPadding
    ) -> some View {
        modifier(GlassCardModifier(radius: radius, padding: padding))
    }
}
