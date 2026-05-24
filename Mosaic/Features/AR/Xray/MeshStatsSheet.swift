//
//  MeshStatsSheet.swift
//  Mosaic
//
//  Detail sheet for the mesh stats capsule. Today shows surface,
//  triangle, and frame-rate counts; per-class breakdown and other
//  diagnostics land here as Track B grows.
//

import SwiftUI

struct MeshStatsSheet: View {
    let faceCount: Int
    let anchorCount: Int
    let fps: Double?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mesh") {
                    LabeledContent("Surfaces") {
                        Text("\(anchorCount)")
                            .font(MosaicFont.monoBody)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Triangles") {
                        Text(faceCount.formatted())
                            .font(MosaicFont.monoBody)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Performance") {
                    LabeledContent("Frames per second") {
                        if let fps {
                            Text("\(Int(fps.rounded()))")
                                .font(MosaicFont.monoBody)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .font(MosaicFont.monoBody)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Mesh Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    MeshStatsSheet(faceCount: 18432, anchorCount: 12, fps: 60)
}
