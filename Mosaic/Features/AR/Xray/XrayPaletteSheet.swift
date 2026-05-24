//
//  XrayPaletteSheet.swift
//  Mosaic
//
//  Stub sheet for per-classification color customization. Today
//  just an informative placeholder; future work replaces the body
//  with a Form / List of the 8 ARMeshClassification cases with a
//  ColorPicker each.
//

import SwiftUI

struct XrayPaletteSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: MosaicSpacing.lg) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .padding(.top, MosaicSpacing.xxl)

                Text("Custom palette coming soon")
                    .font(.system(size: 22, weight: .bold))

                Text("Pick a color for each surface class — walls, floors, ceilings, tables, seats, windows, doors — and watch the X-ray re-tint live.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MosaicSpacing.lg)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Palette")
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

#Preview {
    XrayPaletteSheet()
}
