//
//  HomeView.swift
//  Mosaic
//
//  App root: a hero "Launch AR" button gated on device capability,
//  followed by a readout of device specs, AR capabilities, sensor
//  inventory, and live system state. Settings is reachable via the
//  toolbar gear.
//

import SwiftUI

private enum HomeRoute: Hashable {
    case ar
}

struct HomeView: View {
    @State private var monitor = DeviceMonitor()
    private let device = DeviceInfo.current()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    launchButton
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: MosaicSpacing.sm,
                                                  leading: 0,
                                                  bottom: MosaicSpacing.sm,
                                                  trailing: 0))
                    if let reason = device.unsupportedReason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(MosaicFont.footnote)
                            .foregroundStyle(.orange)
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Device") {
                    infoRow("Model", device.modelIdentifier, icon: "iphone")
                    infoRow("System", "\(device.systemName) \(device.systemVersion)", icon: "apple.logo")
                    infoRow("Memory", String(format: "%.1f GB", device.physicalMemoryGB), icon: "memorychip")
                    infoRow("Cores",  "\(device.processorCount)", icon: "cpu")
                }

                Section {
                    capabilityRow("World tracking",       device.worldTrackingSupported,       icon: "scope")
                    capabilityRow("Scene reconstruction", device.sceneReconstructionSupported, icon: "cube.transparent")
                    capabilityRow("LiDAR (scene depth)",  device.sceneDepthSupported,          icon: "dot.radiowaves.left.and.right")
                } header: {
                    Text("AR Capabilities")
                } footer: {
                    Text("Mosaic requires scene reconstruction with classification — only LiDAR devices.")
                }

                Section("Sensors") {
                    capabilityRow("Back camera",    device.backCameraAvailable, icon: "camera")
                    capabilityRow("Motion sensors", device.motionAvailable,     icon: "gyroscope")
                }

                Section("System State") {
                    HStack {
                        Label("Thermal state", systemImage: "thermometer.medium")
                        Spacer()
                        Text(monitor.thermalState.label)
                            .font(MosaicFont.monoCaption)
                            .foregroundStyle(monitor.thermalState.tintColor)
                    }
                    HStack {
                        Label("Low power mode", systemImage: "battery.25")
                        Spacer()
                        Text(monitor.lowPowerMode ? "On" : "Off")
                            .font(MosaicFont.monoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mosaic")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .ar: ARPlaceholderView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    // MARK: - Hero button

    private var launchButton: some View {
        let supported = device.canRunMosaic
        return NavigationLink(value: HomeRoute.ar) {
            HStack(spacing: MosaicSpacing.md) {
                Image(systemName: "viewfinder")
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: MosaicSpacing.xxs) {
                    Text("Launch AR")
                        .font(MosaicFont.headline)
                    Text(supported ? "Scene reconstruction ready" : "Device not supported")
                        .font(MosaicFont.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "arrow.right")
            }
            .padding(MosaicSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: supported
                        ? [MosaicColor.hudCyan, MosaicColor.accent]
                        : [Color.gray, Color.gray.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: MosaicRadius.lg, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!supported)
    }

    // MARK: - Row helpers

    private func infoRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .font(MosaicFont.monoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func capabilityRow(_ label: String, _ available: Bool, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .red)
        }
    }
}

#Preview("Home · Light") {
    HomeView()
        .environment(AppSettings())
        .preferredColorScheme(.light)
}

#Preview("Home · Dark") {
    HomeView()
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
