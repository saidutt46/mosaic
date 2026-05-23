//
//  ARMessageOverlay.swift
//  Mosaic
//
//  Renders the ARMessages bus over the AR scene. Two independent
//  slots: a small glass chip at the bottom for nudges, and a larger
//  glass card centered for big-moment guidance. White-on-dark forced
//  so text reads on any camera backdrop.
//

import SwiftUI

struct ARMessageOverlay: View {
    @Environment(ARMessages.self) private var messages

    var body: some View {
        ZStack {
            // Bottom-slot chip — now rendered at the vertical center
            // of the AR view; the chip styling (no background, white
            // text + double shadow) is unchanged.
            if let msg = messages.bottom {
                bottomChip(msg)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
            }

            // Center slot — bigger glass card for big-moment guidance.
            // Drawn after the chip so it overlays if both are visible.
            if let msg = messages.center {
                centerCard(msg)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.35), value: messages.bottom?.id)
        .animation(.smooth(duration: 0.35), value: messages.center?.id)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(messages.bottom != nil || messages.center != nil)
    }

    // MARK: - Bottom chip
    //
    // Camera-app style: no background, bold white text, soft double
    // shadow so legibility holds over any backdrop. Centered.

    private func bottomChip(_ msg: ARMessages.Message) -> some View {
        VStack(spacing: MosaicSpacing.sm) {
            if let icon = msg.icon {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(msg.kind.accent)
            }
            Text(msg.text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if case .sticky = msg.lifetime {
                Button {
                    messages.dismiss(msg.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.top, MosaicSpacing.xs)
            }
        }
        .padding(.horizontal, MosaicSpacing.xl)
        .frame(maxWidth: 320)
        .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 2)
    }

    // MARK: - Center card

    private func centerCard(_ msg: ARMessages.Message) -> some View {
        VStack(spacing: MosaicSpacing.md) {
            if let icon = msg.icon {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(msg.kind.accent)
            }
            Text(msg.text)
                .font(MosaicFont.title2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if case .sticky = msg.lifetime {
                Button("Dismiss") { messages.dismiss(msg.id) }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.18))
                    .foregroundStyle(.white)
            }
        }
        .padding(MosaicSpacing.xl)
        .frame(maxWidth: 320)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: MosaicRadius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
    }
}

// MARK: - Preview

#Preview("Overlay") {
    @Previewable @State var messages = ARMessages()

    ZStack {
        LinearGradient(
            colors: [.indigo, .purple, .pink],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ARMessageOverlay()
            .environment(messages)

        VStack(spacing: MosaicSpacing.sm) {
            Spacer()
            Button("Show guidance (bottom)") {
                messages.show("Move your device slowly to scan the space", kind: .guidance)
            }
            Button("Show warning (high)") {
                messages.show("Low light — tracking limited",
                              kind: .warning, source: "ar.tracking")
            }
            Button("Show critical (preempt)") {
                messages.show("Tracking lost",
                              kind: .error, priority: .critical)
            }
            Button("Show center card") {
                messages.show("Point at a wall to begin",
                              kind: .guidance, placement: .center, lifetime: .auto(4))
            }
            Button("Pin sticky center") {
                messages.pin("Tap an item to view its details",
                             kind: .info, placement: .center)
            }
            Button("Clear all") { messages.clearAll() }
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .padding(.bottom, MosaicSpacing.xl)
    }
}
