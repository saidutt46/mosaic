//
//  XrayScanViewer.swift
//  Mosaic
//
//  Detail viewer for a saved scan. Full-screen SceneKit model with a
//  format toggle (mesh USDZ ↔ point cloud PLY), camera reset, an
//  AR/QuickLook hand-off, and share. Floating Liquid-Glass controls
//  over a neutral studio background.
//

import SwiftUI
import QuickLook

struct XrayScanViewer: View {
    let scan: Scan

    // Point cloud is disabled in the viewer until the rendering pass is
    // reworked (points render black / intermittently; camera feels rigid).
    // PLY is still exported; the SceneKit point path stays dormant.
    private let showPointCloud = false

    @State private var resetToken = 0
    @State private var shareItem: ShareItem?
    @State private var previewURL: URL?

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
                    shareCurrent()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .quickLookPreview($previewURL)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: MosaicSpacing.md) {
            glassButton(title: "Reset", icon: "arrow.counterclockwise") {
                resetToken &+= 1
            }

            glassButton(title: "AR", icon: "arkit", isDisabled: meshURL == nil) {
                previewURL = meshURL
            }
        }
        .padding(.trailing, MosaicSpacing.lg)
    }

    private func glassButton(title: String,
                             icon: String,
                             isDisabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: MosaicSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(width: 60, height: 60)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: MosaicRadius.lg))
        .opacity(isDisabled ? 0.4 : 1)
        .disabled(isDisabled)
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
