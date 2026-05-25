//
//  ScanLibraryView.swift
//  Mosaic
//
//  The saved-scans library (E.2.0). An adaptive grid of Apple-Music-
//  style ScanCards — thumbnail, name, mesh stats — newest first.
//  Long-press a card to share or delete. Tapping opens the USDZ in
//  QuickLook (orbit + AR). Reached from the Home "Library" tile.
//

import SwiftUI
import QuickLook

struct ScanLibraryView: View {
    @State private var repo = ScanRepository()
    @State private var previewURL: URL?
    @State private var shareItem: ShareItem?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: MosaicSpacing.lg)
    ]

    var body: some View {
        Group {
            if repo.scans.isEmpty {
                ContentUnavailableView(
                    "No Scans",
                    systemImage: "cube.transparent",
                    description: Text("Saved X-Ray scans appear here. Tap Save while scanning to capture one.")
                )
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: MosaicSpacing.xl) {
                        ForEach(repo.scans) { scan in
                            ScanCard(
                                scan: scan,
                                thumbnailURL: repo.openURL(for: scan.id, artifact: .thumbnail),
                                onTap: { previewURL = repo.openURL(for: scan.id, artifact: .usdz) },
                                onShare: { share(scan) },
                                onDelete: { delete(scan.id) }
                            )
                        }
                    }
                    .padding(.horizontal, MosaicSpacing.screenEdge)
                    .padding(.top, MosaicSpacing.md)
                    .padding(.bottom, MosaicSpacing.xxl)
                }
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .task { await repo.reload() }
        .quickLookPreview($previewURL)
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }

    private func share(_ scan: Scan) {
        if let url = repo.openURL(for: scan.id, artifact: .usdz) {
            shareItem = ShareItem(url: url)
        }
    }

    private func delete(_ id: UUID) {
        Task { try? await repo.delete(id) }
    }
}
