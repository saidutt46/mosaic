//
//  ScanCard.swift
//  Mosaic
//
//  Apple-Music-style tile for a saved scan: square thumbnail with
//  name + stats below, long-press context menu (share / delete).
//  Used in the Library's adaptive grid.
//

import SwiftUI

struct ScanCard: View {
    let scan: Scan
    let thumbnailURL: URL?
    let onTap: () -> Void
    /// Called with the artifact to share. Card surfaces a submenu when
    /// more than just the USDZ is available (e.g. coverage.ply).
    let onShare: (ScanArtifact) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.sm) {
            thumbnailView
                .onTapGesture(perform: onTap)

            VStack(alignment: .leading, spacing: MosaicSpacing.xxs) {
                Text(scan.name)
                    .font(MosaicFont.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statsText)
                    .font(MosaicFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Menu {
                Button { onShare(.usdz) } label: {
                    Label("3D model (USDZ)", systemImage: "cube")
                }
                if scan.artifacts.contains(.pointCloud) {
                    Button { onShare(.pointCloud) } label: {
                        Label("Semantic points (PLY)", systemImage: "paintpalette")
                    }
                }
                if scan.artifacts.contains(.coverage) {
                    Button { onShare(.coverage) } label: {
                        Label("Scan coverage (PLY)", systemImage: "viewfinder")
                    }
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .task(id: thumbnailURL) { loadThumbnail() }
    }

    // MARK: - Thumbnail

    private var thumbnailView: some View {
        let shape = RoundedRectangle(cornerRadius: MosaicRadius.md, style: .continuous)
        // Color.clear anchors a 1:1 square frame; the image lives in an
        // overlay so its (portrait) intrinsic ratio can't leak out and
        // stretch the card. scaledToFill center-crops to the square —
        // no distortion, just trimmed edges.
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        MosaicColor.surface
                        VStack(spacing: MosaicSpacing.xs) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 28, weight: .medium))
                            Text("Scan")
                                .font(MosaicFont.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(MosaicColor.separator, lineWidth: 0.5))
    }

    // MARK: - Content

    private var statsText: String {
        "\(scan.faceCount.formatted()) faces · \(scan.anchorCount) anchors"
    }

    private func loadThumbnail() {
        guard thumbnail == nil, let thumbnailURL,
              let image = UIImage(contentsOfFile: thumbnailURL.path) else { return }
        thumbnail = image
    }
}
