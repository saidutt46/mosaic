//
//  CameraFilterStrip.swift
//  Mosaic
//
//  iOS 26-native camera filter strip. Each chip is its own capsule
//  (dark thin material when unselected, solid hudCyan when active),
//  so there's no wrapping container — the strip scrolls edge-to-edge
//  and the visual "padding" is just the chips' own breathing room.
//
//  - Selection animates with a snappy spring.
//  - The selected chip auto-scrolls to the center.
//  - Selection haptic via sensoryFeedback(.selection).
//
//  Reusable in isolation — see the preview at the bottom.
//

import SwiftUI

struct CameraFilterStrip: View {
    @Binding var selection: CameraFilter

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MosaicSpacing.sm) {
                    ForEach(CameraFilter.allCases) { filter in
                        chip(filter).id(filter.id)
                    }
                }
                .padding(.horizontal, MosaicSpacing.lg)
                .padding(.vertical, MosaicSpacing.xs)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, newValue in
                withAnimation(.snappy(duration: 0.30)) {
                    proxy.scrollTo(newValue.id, anchor: .center)
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
            .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Chip

    private func chip(_ filter: CameraFilter) -> some View {
        let isSelected = selection == filter
        let enabled = filter.isImplemented

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selection = filter
            }
        } label: {
            HStack(spacing: MosaicSpacing.xs) {
                Image(systemName: filter.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(filter.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MosaicSpacing.md)
            .padding(.vertical, MosaicSpacing.sm + 2)
            .background(chipBackground(isSelected: isSelected), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(isSelected ? 0 : 0.18),
                                  lineWidth: 0.5)
            )
            .scaleEffect(isSelected ? 1.0 : 0.96)
            .opacity(enabled ? 1.0 : 0.40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(filter.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func chipBackground(isSelected: Bool) -> AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor)
        } else {
            AnyShapeStyle(.thinMaterial)
        }
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
                .padding(.bottom, MosaicSpacing.sm)
        }
    }
    .preferredColorScheme(.dark)
}
