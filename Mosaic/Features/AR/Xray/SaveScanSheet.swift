//
//  SaveScanSheet.swift
//  Mosaic
//
//  Review sheet shown when the user taps "Done" in the X-Ray session.
//  The AR session is paused behind it. Header + mesh tile row + a tight
//  details panel (extent · coverage · duration) + an expandable class
//  breakdown. Save commits; Close discards after confirm; Resume picks
//  the session back up.
//
//  No hero image / blur — the library card already carries the
//  thumbnail and a full-bleed image cost render time for little value.
//

import SwiftUI
import ARKit

struct SaveScanSheet: View {
    let stats: (anchors: Int, faces: Int, vertices: Int)
    /// World-axis-aligned scan extent in metres. Nil hides the line.
    let extent: SIMD3<Float>?
    /// Coverage voxel snapshot — nil when the coach wasn't used this
    /// session; in that case the coverage row is hidden.
    let coverage: CoverageSnapshot?
    /// Active scan wall-time in seconds (paused intervals excluded).
    let duration: TimeInterval
    /// Per-class face counts keyed by `ARMeshClassification` raw value.
    let classCounts: [UInt8: Int]
    /// Per-class palette (RGB) for the breakdown swatches — matches the
    /// live overlay so the colours read consistently.
    let palette: [SIMD4<Float>]
    let isSaving: Bool

    let onSave: () -> Void
    let onClose: () -> Void
    let onResume: () -> Void

    @State private var showCloseAlert = false
    @State private var classesExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MosaicSpacing.xl) {
                    header
                    statsRow
                    detailsPanel
                    classesDisclosure
                }
                .padding(MosaicSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Save Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { showCloseAlert = true }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: onSave)
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert("Close session?", isPresented: $showCloseAlert) {
                Button("Discard & Close", role: .destructive, action: onClose)
                Button("Resume Scan", role: .cancel, action: onResume)
            } message: {
                Text("Closing discards this scan — nothing will be saved.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(true)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: MosaicSpacing.sm) {
            ZStack {
                Circle()
                    .fill(MosaicColor.accent.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "cube.transparent.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(MosaicColor.accent)
            }
            Text("Scan ready")
                .font(MosaicFont.headline)
            Text("Review the capture and save it to your library.")
                .font(MosaicFont.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, MosaicSpacing.sm)
    }

    // MARK: - Stats tile row

    private var statsRow: some View {
        HStack(spacing: MosaicSpacing.md) {
            statTile("square.grid.3x3.fill", stats.faces, "Faces")
            statTile("cube.fill", stats.anchors, "Anchors")
            statTile("point.3.connected.trianglepath.dotted", stats.vertices, "Vertices")
        }
    }

    private func statTile(_ icon: String, _ value: Int, _ label: String) -> some View {
        VStack(spacing: MosaicSpacing.xs) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(MosaicColor.accent)
            Text(value.formatted())
                .font(MosaicFont.monoBody)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(label)
                .font(MosaicFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MosaicSpacing.lg)
        .background(MosaicColor.surface,
                    in: RoundedRectangle(cornerRadius: MosaicRadius.md, style: .continuous))
    }

    // MARK: - Details panel

    private var detailsPanel: some View {
        VStack(spacing: 0) {
            if let extent {
                detailRow("Scan size", value: format(extent: extent))
                divider
            }
            if let coverage {
                detailRow("Coverage", value: format(coverage: coverage))
                divider
            }
            detailRow("Duration", value: format(duration: duration))
        }
        .padding(.vertical, MosaicSpacing.xs)
        .background(MosaicColor.surface,
                    in: RoundedRectangle(cornerRadius: MosaicRadius.md, style: .continuous))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MosaicFont.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: MosaicSpacing.md)
            Text(value)
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, MosaicSpacing.lg)
        .padding(.vertical, MosaicSpacing.sm)
    }

    private var divider: some View {
        Divider().padding(.leading, MosaicSpacing.lg)
    }

    // MARK: - Classes disclosure

    private var classesDisclosure: some View {
        let visible = ARMeshClassification.allKnown
            .map { ($0, classCounts[UInt8($0.rawValue)] ?? 0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        return DisclosureGroup(isExpanded: $classesExpanded) {
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.offset) { (idx, entry) in
                    classRow(entry.0, count: entry.1)
                    if idx < visible.count - 1 { divider }
                }
            }
            .padding(.vertical, MosaicSpacing.xs)
            .background(MosaicColor.surface,
                        in: RoundedRectangle(cornerRadius: MosaicRadius.md, style: .continuous))
            .padding(.top, MosaicSpacing.xs)
        } label: {
            HStack {
                Text("Classes")
                    .font(MosaicFont.callout)
                Spacer()
                Text("\(visible.count)")
                    .font(MosaicFont.monoCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, MosaicSpacing.lg)
        .padding(.vertical, MosaicSpacing.sm)
        .background(MosaicColor.surface,
                    in: RoundedRectangle(cornerRadius: MosaicRadius.md, style: .continuous))
    }

    private func classRow(_ cls: ARMeshClassification, count: Int) -> some View {
        let raw = Int(cls.rawValue)
        let color: Color = (raw < palette.count)
            ? Color(red: Double(palette[raw].x),
                    green: Double(palette[raw].y),
                    blue: Double(palette[raw].z))
            : .secondary

        return HStack(spacing: MosaicSpacing.sm) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(cls.displayName)
                .font(MosaicFont.callout)
            Spacer()
            Text(count.formatted())
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MosaicSpacing.lg)
        .padding(.vertical, MosaicSpacing.sm)
    }

    // MARK: - Formatting

    private func format(extent: SIMD3<Float>) -> String {
        String(format: "%.1f × %.1f × %.1f m", extent.x, extent.y, extent.z)
    }

    private func format(coverage: CoverageSnapshot) -> String {
        let pct = Int((coverage.wellCoveredFraction() * 100).rounded())
        return "\(pct)% · \(coverage.count.formatted()) voxels"
    }

    private func format(duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Previews

private struct SaveScanSheetPreview: View {
    var isSaving = false
    var coverage: CoverageSnapshot? = CoverageSnapshot(
        voxelSize: 0.05,
        points: (0..<1432).map { i in
            SIMD4<Float>(0, 0, 0, Float(i % 100) / 100.0)
        }
    )
    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                SaveScanSheet(
                    stats: (anchors: 16, faces: 151_503, vertices: 84_207),
                    extent: SIMD3<Float>(4.2, 3.1, 2.4),
                    coverage: coverage,
                    duration: 154,
                    classCounts: [
                        1: 78_432, // wall
                        2: 23_109, // floor
                        4: 12_890, // table
                        0: 8_432,  // none
                    ],
                    palette: MeshOverlayPass.defaultPalette,
                    isSaving: isSaving,
                    onSave: {}, onClose: {}, onResume: {}
                )
            }
    }
}

#Preview("Save Scan · Light") {
    SaveScanSheetPreview().preferredColorScheme(.light)
}

#Preview("Save Scan · Dark") {
    SaveScanSheetPreview().preferredColorScheme(.dark)
}

#Preview("Save Scan · Saving") {
    SaveScanSheetPreview(isSaving: true)
}

#Preview("Save Scan · No coverage") {
    SaveScanSheetPreview(coverage: nil).preferredColorScheme(.dark)
}
