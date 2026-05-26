//
//  SettingsView.swift
//  Mosaic
//
//  Top-level Settings screen. Native iOS Form for system-feel; gets
//  Liquid Glass chrome automatically on iOS 26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = services.settings

        Form {
            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle(isOn: $settings.showControlLabels) {
                    Label("Show control labels", systemImage: "textformat.size")
                }
            } header: {
                Text("Viewer")
            } footer: {
                Text("Show text labels under the 3D viewer's floating controls.")
            }

            Section("Debug") {
                NavigationLink {
                    DesignGallery()
                        .navigationTitle("Design Gallery")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Design Gallery", systemImage: "paintpalette")
                }
            }

            Section {
                aboutRow("App",     value: AboutInfo.appName)
                aboutRow("Version", value: AboutInfo.versionString)
                aboutRow("Build",   value: AboutInfo.build)
            } header: {
                Text("About")
            } footer: {
                Text(AboutInfo.tagline)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ key: String, value: String) -> some View {
        LabeledContent(key) {
            Text(value).font(MosaicFont.monoCaption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - About info

enum AboutInfo {
    static let appName = "Mosaic"
    static let tagline = "Semantic mesh visualizer — ARKit + Metal."

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var versionString: String { "\(version) (\(build))" }
}

// MARK: - Preview

#Preview("Settings · Light") {
    NavigationStack { SettingsView() }
        .environment(AppServices())
        .preferredColorScheme(.light)
}

#Preview("Settings · Dark") {
    NavigationStack { SettingsView() }
        .environment(AppServices())
        .preferredColorScheme(.dark)
}
