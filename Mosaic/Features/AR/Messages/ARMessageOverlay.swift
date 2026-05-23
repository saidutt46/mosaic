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
            // Center slot
            if let msg = messages.center {
                centerCard(msg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            // Bottom slot
            if let msg = messages.bottom {
                VStack {
                    Spacer()
                    bottomChip(msg)
                        .padding(.bottom, MosaicSpacing.xxl)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(MosaicMotion.snappy, value: messages.bottom?.id)
        .animation(MosaicMotion.smooth, value: messages.center?.id)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(messages.bottom != nil || messages.center != nil)
    }

    // MARK: - Bottom chip

    private func bottomChip(_ msg: ARMessages.Message) -> some View {
        HStack(spacing: MosaicSpacing.sm) {
            if let icon = msg.icon {
                Image(systemName: icon)
                    .foregroundStyle(msg.kind.accent)
            }
            Text(msg.text)
                .font(MosaicFont.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if case .sticky = msg.lifetime {
                Button {
                    messages.dismiss(msg.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, MosaicSpacing.xs)
            }
        }
        .padding(.horizontal, MosaicSpacing.lg)
        .padding(.vertical, MosaicSpacing.md)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
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
