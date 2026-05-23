//
//  CameraFilterStrip.swift
//  Mosaic
//
//  Instagram-style horizontal filter strip mounted at the bottom of
//  the AR view. Each chip is an icon + label VStack; the active
//  chip tints to MosaicColor.hudCyan, unimplemented chips dim out.
//
//  Reusable in isolation — the SwiftUI preview at the bottom of
//  this file is the iteration playground. Tweak chip width / icon
//  size / shadows there and the AR view picks it up unchanged.
//

import SwiftUI

struct CameraFilterStrip: View {
    @Binding var selection: CameraFilter

    private let chipSize = CGSize(width: 64, height: 60)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MosaicSpacing.sm) {
                ForEach(CameraFilter.allCases) { filter in
                    chip(filter)
                }
            }
            .padding(.horizontal, MosaicSpacing.lg)
            .padding(.vertical, MosaicSpacing.md)
        }
        .scrollIndicators(.hidden)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Chip

    private func chip(_ filter: CameraFilter) -> some View {
        let isSelected = selection == filter
        let enabled = filter.isImplemented

        return Button {
            withAnimation(MosaicMotion.snappy) {
                selection = filter
            }
        } label: {
            VStack(spacing: MosaicSpacing.xs) {
                Image(systemName: filter.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(filter.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: chipSize.width, height: chipSize.height)
            .foregroundStyle(isSelected ? MosaicColor.hudCyan : Color.white)
            .opacity(enabled ? 1.0 : 0.30)
            .shadow(color: .black.opacity(0.85), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(filter.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview("Filter strip · over gradient") {
    @Previewable @State var selection: CameraFilter = .none

    ZStack {
        // Pretend AR backdrop so we can judge legibility.
        LinearGradient(
            colors: [.indigo, .purple, .pink, .orange],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            CameraFilterStrip(selection: $selection)
        }
    }
    .preferredColorScheme(.dark)
}
