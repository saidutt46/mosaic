//
//  SectionLabel.swift
//  Mosaic
//
//  Small uppercase section header — used inside cards and grouped lists
//  to introduce a sub-region without claiming a full title slot.
//

import SwiftUI

struct SectionLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: MosaicSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title.uppercased())
                .tracking(1.2)
        }
        .font(MosaicFont.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: MosaicSpacing.md) {
        SectionLabel(title: "Surfaces", systemImage: "square.stack.3d.up")
        SectionLabel(title: "Classification")
    }
    .padding()
}
