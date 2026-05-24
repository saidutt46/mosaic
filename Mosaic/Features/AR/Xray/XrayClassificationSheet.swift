//
//  XrayClassificationSheet.swift
//  Mosaic
//
//  Per-classification color picker + visibility toggle. One row per
//  ARMeshClassification case. Hidden classes dim to 40% opacity in
//  the form AND get discard_fragment'd in the shader (no depth
//  write, no occlusion).
//

import SwiftUI

struct XrayClassificationSheet: View {
    @Bindable var styles: ClassificationStyles

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($styles.entries) { $entry in
                        HStack(spacing: MosaicSpacing.md) {
                            ColorPicker("", selection: $entry.color, supportsOpacity: false)
                                .labelsHidden()
                                .fixedSize()

                            Text(entry.classification.label.capitalized)
                                .font(MosaicFont.body)

                            Spacer()

                            Toggle("", isOn: $entry.isVisible)
                                .labelsHidden()
                        }
                        .opacity(entry.isVisible ? 1.0 : 0.4)
                        .animation(MosaicMotion.snappy, value: entry.isVisible)
                    }
                } header: {
                    Text("Classes")
                } footer: {
                    Text("Tap a color to customize it. Toggle off to hide that class entirely — hidden surfaces don't draw or occlude.")
                }

                Section {
                    Button(role: .destructive) {
                        withAnimation(MosaicMotion.snappy) {
                            styles.reset()
                        }
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Classification")
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
    XrayClassificationSheet(styles: ClassificationStyles())
}
