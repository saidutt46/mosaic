//
//  ScanLibraryView.swift
//  Mosaic
//
//  The saved-scans library (Phase E.2.0). Lists every scan in
//  Documents/Scans/ — thumbnail, name, date, mesh stats — newest
//  first. Swipe to delete. Tapping a scan opens its USDZ in QuickLook
//  (orbit + AR preview). Reached from the Home "Library" tile.
//

import SwiftUI
import QuickLook

struct ScanLibraryView: View {
    @State private var repo = ScanRepository()
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if repo.scans.isEmpty {
                ContentUnavailableView(
                    "No Scans",
                    systemImage: "cube.transparent",
                    description: Text("Saved X-Ray scans appear here. Tap Save while scanning to capture one.")
                )
            } else {
                List {
                    ForEach(repo.scans) { scan in
                        Button {
                            previewURL = repo.openURL(for: scan.id, artifact: .usdz)
                        } label: {
                            ScanRow(scan: scan,
                                    thumbnailURL: repo.openURL(for: scan.id, artifact: .thumbnail))
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .task { await repo.reload() }
        .quickLookPreview($previewURL)
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { repo.scans[$0].id }
        Task {
            for id in ids { try? await repo.delete(id) }
        }
    }
}

// MARK: - Row

private struct ScanRow: View {
    let scan: Scan
    let thumbnailURL: URL?

    var body: some View {
        HStack(spacing: MosaicSpacing.md) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("\(scan.faceCount.formatted()) faces · \(scan.anchorCount) anchors")
                    .font(MosaicFont.monoCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, MosaicSpacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: MosaicRadius.md, style: .continuous)
        Group {
            if let thumbnailURL, let image = UIImage(contentsOfFile: thumbnailURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                shape.fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(shape)
    }
}
