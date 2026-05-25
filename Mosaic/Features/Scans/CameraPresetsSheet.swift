//
//  CameraPresetsSheet.swift
//  Mosaic
//
//  Grid picker for the viewer's camera angles. Tapping a preset applies
//  it and dismisses. The active preset is highlighted.
//

import SwiftUI

struct CameraPresetsSheet: View {
    let current: CameraPreset
    let onSelect: (CameraPreset) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: MosaicSpacing.md)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: MosaicSpacing.md) {
                    ForEach(CameraPreset.allCases) { preset in
                        presetButton(preset)
                    }
                }
                .padding(MosaicSpacing.lg)
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
    }

    private func presetButton(_ preset: CameraPreset) -> some View {
        let isActive = preset == current
        let shape = RoundedRectangle(cornerRadius: MosaicRadius.md, style: .continuous)
        return Button {
            onSelect(preset)
            dismiss()
        } label: {
            VStack(spacing: MosaicSpacing.xs) {
                Image(systemName: preset.icon)
                    .font(.title3.weight(.semibold))
                Text(preset.label)
                    .font(MosaicFont.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .foregroundStyle(isActive ? MosaicColor.accent : .primary)
            .background(.thinMaterial, in: shape)
            .overlay {
                if isActive {
                    shape.strokeBorder(MosaicColor.accent.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
