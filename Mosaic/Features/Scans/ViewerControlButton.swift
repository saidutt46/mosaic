//
//  ViewerControlButton.swift
//  Mosaic
//
//  A floating Liquid-Glass control for the scan detail viewer. Shows an
//  icon, plus a text label when AppSettings.showControlLabels is on
//  (off by default). Used in the viewer's right-edge control cluster.
//

import SwiftUI

struct ViewerControlButton: View {
    @Environment(AppSettings.self) private var settings

    let title: String
    let icon: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MosaicSpacing.xxs) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                if settings.showControlLabels {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .frame(width: 56, height: settings.showControlLabels ? 58 : 48)
            .contentShape(Rectangle())
            .foregroundStyle(isActive ? MosaicColor.accent : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: MosaicRadius.lg))
        .opacity(isDisabled ? 0.4 : 1)
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}
