//
//  ViewerControlButton.swift
//  Mosaic
//
//  Floating Liquid-Glass controls for the scan / X-Ray HUD. Each shows an
//  icon plus a text label when AppSettings.showControlLabels is on (off by
//  default). `ViewerControlButton` fires an action; `ViewerControlMenu`
//  opens a pull-down menu (both share the same glyph + glass styling).
//

import SwiftUI

/// Shared icon-over-optional-label glyph used by both control variants.
private struct ControlGlyph: View {
    @Environment(AppServices.self) private var services
    private var settings: AppSettings { services.settings }

    let title: String
    let icon: String
    var isActive: Bool = false
    var animatesWhenActive: Bool = false

    var body: some View {
        VStack(spacing: MosaicSpacing.xxs) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .symbolEffect(.variableColor.iterative,
                              isActive: animatesWhenActive && isActive)
            if settings.showControlLabels {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .frame(width: 56, height: settings.showControlLabels ? 58 : 48)
        .contentShape(Rectangle())
        .foregroundStyle(isActive ? MosaicColor.accent : .primary)
    }
}

struct ViewerControlButton: View {
    let title: String
    let icon: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    /// Animate the symbol with a flowing variable-colour effect while
    /// active (used by the density toggle to signal the live ramp).
    var animatesWhenActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ControlGlyph(title: title, icon: icon,
                         isActive: isActive,
                         animatesWhenActive: animatesWhenActive)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: MosaicRadius.lg))
        .opacity(isDisabled ? 0.4 : 1)
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

/// A control that opens a pull-down menu instead of firing an action.
/// Matches `ViewerControlButton`'s glass styling.
struct ViewerControlMenu<Content: View>: View {
    let title: String
    let icon: String
    var isActive: Bool = false
    var animatesWhenActive: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            ControlGlyph(title: title, icon: icon,
                         isActive: isActive,
                         animatesWhenActive: animatesWhenActive)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: MosaicRadius.lg))
        .accessibilityLabel(title)
    }
}
