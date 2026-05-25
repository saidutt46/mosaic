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
    @State private var selectedScan: Scan?
    @State private var shareItem: ShareItem?
    @State private var scanToDelete: Scan?

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
                                onTap: { selectedScan = scan },
                                onShare: { share(scan) },
                                onDelete: { scanToDelete = scan }
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
        .navigationDestination(item: $selectedScan) { XrayScanViewer(scan: $0) }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .alert(
            "Delete Scan?",
            isPresented: Binding(get: { scanToDelete != nil },
                                 set: { if !$0 { scanToDelete = nil } }),
            presenting: scanToDelete
        ) { scan in
            Button("Delete", role: .destructive) { delete(scan.id) }
            Button("Cancel", role: .cancel) {}
        } message: { scan in
            Text("“\(scan.name)” and its files will be permanently deleted. This can’t be undone.")
        }
    }

    private func share(_ scan: Scan) {
        guard let source = repo.openURL(for: scan.id, artifact: .usdz),
              let shareURL = ShareFile.prepared(from: source, named: scan.name) else { return }
        shareItem = ShareItem(url: shareURL)
    }

    private func delete(_ id: UUID) {
        Task { try? await repo.delete(id) }
    }
}
