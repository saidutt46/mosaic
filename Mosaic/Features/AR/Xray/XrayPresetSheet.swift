//
//  XrayPresetSheet.swift
//  Mosaic
//
//  Style preset picker for XrayView. 2×2 grid of hero cards; each
//  card previews the preset's palette + name + caption. Tapping a
//  card hard-resets every mesh control to the preset's values; the
//  classification sheet reflects the new values immediately so the
//  user can still tune anything afterwards.
//

import SwiftUI

struct XrayPresetSheet: View {
    let onApply: (MeshPreset) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: MosaicSpacing.md),
        GridItem(.flexible(), spacing: MosaicSpacing.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: MosaicSpacing.md) {
                    ForEach(MeshPreset.allCases) { preset in
                        PresetCard(preset: preset) {
                            onApply(preset)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, MosaicSpacing.lg)
                .padding(.top, MosaicSpacing.md)
                .padding(.bottom, MosaicSpacing.xl)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preset card

private struct PresetCard: View {
    let preset: MeshPreset
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: MosaicSpacing.md) {
                swatches
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(preset.caption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(MosaicSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 180)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: MosaicRadius.xl,
                                     style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) preset")
        .accessibilityHint(preset.caption)
    }

    /// 2×2 mini grid of the four preview colours so the card reads
    /// as "here's what walls / floor / ceiling / seats look like."
    private var swatches: some View {
        let colors = preset.previewColors  // 4 colours
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 4),
                      GridItem(.flexible(), spacing: 4)],
            spacing: 4
        ) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    XrayPresetSheet { _ in }
}
