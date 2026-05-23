//
//  DesignGallery.swift
//  Mosaic
//
//  Single-screen showcase of every design token + reusable surface.
//  Open in Xcode Previews (Light/Dark variants) to verify the design
//  language end-to-end whenever a token changes.
//

import SwiftUI

struct DesignGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MosaicSpacing.xl) {
                header
                surfacesSection
                brandSection
                classificationSection
                typographySection
                spacingSection
                radiusSection
                glassCardSection
                hudSampleSection
            }
            .padding(MosaicSpacing.screenEdge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MosaicColor.background.ignoresSafeArea())
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.xs) {
            Text("Mosaic").font(MosaicFont.display)
            Text("Design System · v0.1")
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private var surfacesSection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            SectionLabel(title: "Surfaces", systemImage: "square.stack.3d.up")
            HStack(spacing: MosaicSpacing.sm) {
                swatch("background", MosaicColor.background)
                swatch("surface", MosaicColor.surface)
                swatch("grouped", MosaicColor.groupedBackground)
            }
        }
    }

    private var brandSection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            SectionLabel(title: "Brand", systemImage: "paintpalette")
            HStack(spacing: MosaicSpacing.sm) {
                swatch("accent", MosaicColor.accent)
                swatch("hudCyan", MosaicColor.hudCyan)
                swatch("hudMagenta", MosaicColor.hudMagenta)
            }
        }
    }

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            SectionLabel(title: "Classification Palette", systemImage: "cube.transparent")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: MosaicSpacing.sm), count: 4),
                spacing: MosaicSpacing.sm
            ) {
                ForEach(MosaicColor.Classification.all, id: \.name) { entry in
                    swatch(entry.name, entry.color)
                }
            }
            Text("Mapped 1:1 to ARMeshClassification — reused by the Metal mesh overlay and UI swatches.")
                .font(MosaicFont.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.sm) {
            SectionLabel(title: "Typography", systemImage: "textformat")
            Text("Display").font(MosaicFont.display)
            Text("Title").font(MosaicFont.title)
            Text("Title 2").font(MosaicFont.title2)
            Text("Headline").font(MosaicFont.headline)
            Text("Body — the quick brown fox jumps over the lazy dog.")
                .font(MosaicFont.body)
            Text("Callout").font(MosaicFont.callout)
            Text("Footnote").font(MosaicFont.footnote).foregroundStyle(.secondary)
            Text("Caption").font(MosaicFont.caption).foregroundStyle(.secondary)
            Divider().padding(.vertical, MosaicSpacing.xs)
            Text("mono · 0123456789 ABCxyz").font(MosaicFont.monoBody)
            Text("60.0 FPS").font(MosaicFont.monoFigure).foregroundStyle(MosaicColor.hudCyan)
        }
    }

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            SectionLabel(title: "Spacing · 4pt grid", systemImage: "ruler")
            VStack(alignment: .leading, spacing: MosaicSpacing.xs) {
                spacingRow("xs",   MosaicSpacing.xs)
                spacingRow("sm",   MosaicSpacing.sm)
                spacingRow("md",   MosaicSpacing.md)
                spacingRow("lg",   MosaicSpacing.lg)
                spacingRow("xl",   MosaicSpacing.xl)
                spacingRow("xxl",  MosaicSpacing.xxl)
                spacingRow("xxxl", MosaicSpacing.xxxl)
            }
        }
    }

    private var radiusSection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            SectionLabel(title: "Radii", systemImage: "app.badge")
            HStack(spacing: MosaicSpacing.md) {
                radiusChip("sm", MosaicRadius.sm)
                radiusChip("md", MosaicRadius.md)
                radiusChip("lg", MosaicRadius.lg)
                radiusChip("xl", MosaicRadius.xl)
            }
        }
    }

    private var glassCardSection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            SectionLabel(title: "Glass Card", systemImage: "square.on.square")
            VStack(alignment: .leading, spacing: MosaicSpacing.sm) {
                Text("Liquid Glass surface").font(MosaicFont.headline)
                Text("Floating overlay for settings, HUD readouts, palette pickers.")
                    .font(MosaicFont.footnote)
                    .foregroundStyle(.secondary)
            }
            .glassCard()
            .background(
                // Backdrop so the material has something to blur over
                LinearGradient(
                    colors: [MosaicColor.hudCyan, MosaicColor.hudMagenta],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .opacity(0.25)
                .clipShape(RoundedRectangle(cornerRadius: MosaicRadius.lg, style: .continuous))
            )
        }
    }

    private var hudSampleSection: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            SectionLabel(title: "HUD Sample", systemImage: "viewfinder")
            HStack {
                Label("60 FPS", systemImage: "gauge.with.dots.needle.67percent")
                Spacer()
                Label("12 anchors", systemImage: "cube")
                Spacer()
                Label("3.2k tris", systemImage: "triangle")
            }
            .font(MosaicFont.monoCaption)
            .foregroundStyle(MosaicColor.hudCyan)
            .glassCard(radius: MosaicRadius.md, padding: MosaicSpacing.md)
        }
    }

    // MARK: Helpers

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: MosaicSpacing.xs) {
            RoundedRectangle(cornerRadius: MosaicRadius.sm, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: MosaicRadius.sm, style: .continuous)
                        .strokeBorder(MosaicColor.hairline, lineWidth: 0.5)
                )
                .frame(height: 56)
            Text(name)
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func spacingRow(_ name: String, _ size: CGFloat) -> some View {
        HStack(spacing: MosaicSpacing.sm) {
            Text(name)
                .font(MosaicFont.monoCaption)
                .frame(width: 36, alignment: .leading)
            RoundedRectangle(cornerRadius: 2)
                .fill(MosaicColor.accent)
                .frame(width: size, height: 10)
            Text("\(Int(size))pt")
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func radiusChip(_ name: String, _ r: CGFloat) -> some View {
        VStack(spacing: MosaicSpacing.xs) {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(MosaicColor.accent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(MosaicColor.accent, lineWidth: 1)
                )
                .frame(width: 64, height: 48)
            Text("\(name) · \(Int(r))")
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Gallery · Light") {
    DesignGallery().preferredColorScheme(.light)
}

#Preview("Gallery · Dark") {
    DesignGallery().preferredColorScheme(.dark)
}
