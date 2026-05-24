//
//  MeshStatsCapsule.swift
//  Mosaic
//
//  Compact live HUD for XrayView. Two stat blocks side by side:
//
//    ▲ 18.4k   60 fps
//
//  Designed to live inside `ToolbarItem(placement: .bottomBar)` —
//  iOS 26's toolbar provides the Liquid Glass capsule, tint, and
//  shadow automatically. This view contributes only the content.
//
//  Tapping fires the supplied action — XrayView opens a detail
//  sheet (anchor count, per-class breakdown, etc.) on tap.
//

import SwiftUI

struct MeshStatsCapsule: View {

    let faceCount: Int
    let fps: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MosaicSpacing.sm) {
                iconStat(icon: "triangle.fill",
                         value: formatCount(faceCount))
                if let fps {
                    unitStat(value: "\(Int(fps.rounded()))",
                             unit: "fps")
                }
            }
            .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Stat blocks

    /// Icon-leading stat block (e.g. ▲ 18.4k).
    private func iconStat(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.85)
            Text(value)
                .font(.system(size: 13, weight: .semibold,
                              design: .monospaced))
        }
    }

    /// Value + text-unit stat block (e.g. 60 fps).
    private func unitStat(value: String, unit: String) -> some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold,
                              design: .monospaced))
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.7)
        }
    }

    // MARK: - Helpers

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private var accessibilityDescription: String {
        var parts: [String] = ["\(faceCount) triangles"]
        if let fps {
            parts.append("\(Int(fps.rounded())) frames per second")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("In bottom toolbar") {
    NavigationStack {
        ZStack {
            LinearGradient(
                colors: [.black, .indigo, .purple],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            Text("(camera feed)")
                .foregroundStyle(.white.opacity(0.5))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { } label: { Image(systemName: "xmark") }
            }

            ToolbarItem(placement: .bottomBar) {
                MeshStatsCapsule(faceCount: 18432, fps: 60) {}
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button { } label: { Image(systemName: "paintpalette.fill") }
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button { } label: { Image(systemName: "camera.fill") }
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button { } label: { Image(systemName: "cube.fill") }
            }
        }
    }
    .preferredColorScheme(.dark)
}
