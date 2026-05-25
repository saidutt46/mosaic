//
//  SaveScanSheet.swift
//  Mosaic
//
//  Review sheet shown when the user taps "Done" in the X-Ray session.
//  The AR session is paused behind it. Shows a quick header + mesh
//  stats; Save commits the scan, Close discards the session (after
//  confirm) or resumes scanning.
//
//  Deliberately no hero image / blur — a full-bleed image in a medium
//  sheet cost render time for little value (the library cards already
//  carry the thumbnail).
//

import SwiftUI

struct SaveScanSheet: View {
    let stats: (anchors: Int, faces: Int, vertices: Int)
    let isSaving: Bool

    let onSave: () -> Void
    let onClose: () -> Void
    let onResume: () -> Void

    @State private var showCloseAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: MosaicSpacing.xl) {
                header
                statsRow
                Spacer(minLength: 0)
            }
            .padding(MosaicSpacing.xl)
            .frame(maxWidth: .infinity)
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
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

    // MARK: - Stats

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
}

// MARK: - Previews

private struct SaveScanSheetPreview: View {
    var isSaving = false
    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                SaveScanSheet(
                    stats: (anchors: 16, faces: 151_503, vertices: 84_207),
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
