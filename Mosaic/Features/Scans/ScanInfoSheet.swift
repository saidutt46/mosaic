//
//  ScanInfoSheet.swift
//  Mosaic
//
//  Metadata sheet for a saved scan, opened from the viewer's info
//  button: name, capture date, mesh stats, and the artifact files
//  on disk with their sizes.
//

import SwiftUI

struct ScanInfoSheet: View {
    let scan: Scan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Scan") {
                    LabeledContent("Name", value: scan.name)
                    LabeledContent("Created", value: scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section("Mesh") {
                    statRow("Faces", scan.faceCount)
                    statRow("Anchors", scan.anchorCount)
                    statRow("Vertices", scan.vertexCount)
                }

                Section("Files") {
                    ForEach(scan.artifacts, id: \.self) { artifact in
                        LabeledContent(artifact.filename) {
                            Text(fileSize(for: artifact))
                                .font(MosaicFont.monoCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Scan Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func statRow(_ label: String, _ value: Int) -> some View {
        LabeledContent(label) {
            Text(value.formatted())
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func fileSize(for artifact: ScanArtifact) -> String {
        let url = DocumentsURL.artifactURL(scanID: scan.id, artifact)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
