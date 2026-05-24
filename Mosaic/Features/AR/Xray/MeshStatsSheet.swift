//
//  MeshStatsSheet.swift
//  Mosaic
//
//  Detail sheet for the mesh stats capsule. Shows live surface /
//  triangle / FPS counts and exposes the mesh-density control
//  (dropdown). Future Track B controls (per-class colour picker,
//  effects toggles, etc.) land here as more sections.
//

import SwiftUI

struct MeshStatsSheet: View {
    let faceCount: Int
    let anchorCount: Int
    let fps: Double?
    @Binding var density: MeshDensity
    @Binding var fresnelIntensity: Float

    @Environment(\.dismiss) private var dismiss

    private var visibleFaceCount: Int {
        guard density.rawValue > 0 else { return faceCount }
        return faceCount / Int(density.rawValue)
    }

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
                    LabeledContent("Drawn") {
                        Text(visibleFaceCount.formatted())
                            .font(MosaicFont.monoBody)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Render") {
                    Picker(selection: $density) {
                        ForEach(MeshDensity.allCases) { d in
                            Text("\(d.label) · \(d.percentLabel)").tag(d)
                        }
                    } label: {
                        Label("Density", systemImage: "circle.grid.3x3")
                    }
                    .pickerStyle(.menu)
                }

                Section("Effects") {
                    VStack(alignment: .leading, spacing: MosaicSpacing.xs) {
                        HStack {
                            Label("Edge glow", systemImage: "sparkles")
                            Spacer()
                            Text("\(Int(fresnelIntensity * 100))%")
                                .font(MosaicFont.monoCaption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $fresnelIntensity, in: 0...1)
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
    @Previewable @State var density: MeshDensity = .full
    @Previewable @State var fresnel: Float = 0.0
    MeshStatsSheet(
        faceCount: 18432,
        anchorCount: 12,
        fps: 60,
        density: $density,
        fresnelIntensity: $fresnel
    )
}
