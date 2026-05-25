//
//  XrayScanViewer.swift
//  Mosaic
//
//  Detail viewer for a saved scan. Full-screen SceneKit model over a
//  neutral studio background. Right-edge floating controls (mesh ↔
//  solid, reset). Top bar: info + overflow menu (share + more). Bottom
//  bar: AR/QuickLook. Point cloud is disabled in the viewer until the
//  rendering pass is reworked.
//

import SwiftUI
import QuickLook

struct XrayScanViewer: View {
    let scan: Scan

    private let showPointCloud = false

    @State private var wireframe = false
    @State private var resetToken = 0
    @State private var shareItem: ShareItem?
    @State private var previewURL: URL?
    @State private var showingInfo = false

    private var meshURL: URL? { artifactURL(.usdz) }
    private var pointCloudURL: URL? { artifactURL(.pointCloud) }

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
                .ignoresSafeArea()

            SceneKitModelView(
                meshURL: meshURL,
                pointCloudURL: pointCloudURL,
                showPointCloud: showPointCloud,
                wireframe: wireframe,
                resetToken: resetToken
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .trailing) { controls }
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    previewURL = meshURL
                } label: {
                    Image(systemName: "arkit")
                }
                .disabled(meshURL == nil)
                .accessibilityLabel("View in AR")
            }
        }
        .sheet(isPresented: $showingInfo) { ScanInfoSheet(scan: scan) }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .quickLookPreview($previewURL)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: MosaicSpacing.md) {
            ViewerControlButton(
                title: "Mesh",
                icon: "grid",
                isActive: wireframe
            ) {
                withAnimation(MosaicMotion.snappy) { wireframe.toggle() }
            }

            ViewerControlButton(title: "Reset", icon: "arrow.counterclockwise") {
                resetToken &+= 1
            }
        }
        .padding(.trailing, MosaicSpacing.lg)
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                shareCurrent()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Section {
                // Placeholders — wired up in a later pass.
                Button {} label: { Label("Rename", systemImage: "pencil") }
                    .disabled(true)
                Button {} label: { Label("Add to Collection", systemImage: "folder.badge.plus") }
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Actions

    private func shareCurrent() {
        guard let source = meshURL,
              let shareURL = ShareFile.prepared(from: source, named: scan.name) else { return }
        shareItem = ShareItem(url: shareURL)
    }

    private func artifactURL(_ artifact: ScanArtifact) -> URL? {
        let url = DocumentsURL.artifactURL(scanID: scan.id, artifact)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
