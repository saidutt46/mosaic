//
//  SettingsView.swift
//  Mosaic
//
//  Top-level Settings screen. Native iOS Form for system-feel; gets
//  Liquid Glass chrome automatically on iOS 26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle(isOn: $settings.showDebugOverlay) {
                    Label("Show debug overlay", systemImage: "gauge.with.dots.needle.67percent")
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Displays FPS, anchor count, and triangle count over the AR view.")
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
        .environment(AppSettings())
        .preferredColorScheme(.light)
}

#Preview("Settings · Dark") {
    NavigationStack { SettingsView() }
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
