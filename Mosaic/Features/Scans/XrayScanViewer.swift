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

    @Environment(AppServices.self) private var services
    private var repo: ScanRepository { services.scans }
    @State private var cameraPreset: CameraPreset = .default
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var classificationStyles = ClassificationStyles()
    @State private var meshOpacity: Float = 1.0
    @State private var showingLayers = false
    @State private var presetToken = 0
    @State private var resetToken = 0
    @State private var shareItem: ShareItem?
    @State private var previewURL: URL?
    @State private var showingInfo = false
    @State private var showingPresets = false
    @State private var isLoading = true

    private var meshURL: URL? { artifactURL(.usdz) }

    /// Live scan from the shared repo (reflects renames); falls back to
    /// the value we were navigated with.
    private var currentScan: Scan { repo.scans.first { $0.id == scan.id } ?? scan }

    var body: some View {
        ZStack {
            RealityModelView(
                modelURL: meshURL,
                preset: cameraPreset,
                presetToken: presetToken,
                resetToken: resetToken,
                palette: classificationStyles.palette,
                visibilityMask: classificationStyles.visibilityMask,
                opacity: meshOpacity,
                onLoaded: { isLoading = false }
            )
            .ignoresSafeArea()

            if isLoading { loadingOverlay }
        }
        .overlay(alignment: .trailing) { controls }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
        .sheet(isPresented: $showingInfo) { ScanInfoSheet(scan: currentScan) }
        .alert("Rename Scan", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                Task { try? await repo.rename(scan.id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingPresets) {
            CameraPresetsSheet(current: cameraPreset) { preset in
                cameraPreset = preset
                presetToken &+= 1
            }
        }
        .sheet(isPresented: $showingLayers) {
            XrayClassificationSheet(styles: classificationStyles, opacity: $meshOpacity)
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .quickLookPreview($previewURL)
    }

    // MARK: - Controls

    private var loadingOverlay: some View {
        VStack(spacing: MosaicSpacing.md) {
            ProgressView()
            Text("Loading scan…")
                .font(MosaicFont.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: MosaicSpacing.md) {
            ViewerControlButton(title: "Layers", icon: "square.3.layers.3d") {
                showingLayers = true
            }

            ViewerControlButton(title: "Camera", icon: "camera.aperture") {
                showingPresets = true
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
            Button {
                renameText = currentScan.name
                showingRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Section {
                // Placeholder — wired up in a later pass.
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
              let shareURL = ShareFile.prepared(from: source, named: currentScan.name) else { return }
        shareItem = ShareItem(url: shareURL)
    }

    private func artifactURL(_ artifact: ScanArtifact) -> URL? {
        let url = DocumentsURL.artifactURL(scanID: scan.id, artifact)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
