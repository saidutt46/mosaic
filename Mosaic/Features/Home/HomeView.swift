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
                case .ar: ARView()
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                launchBar
            }
        }
    }

    // MARK: - Launch bar (bottom-pinned)

    private var launchBar: some View {
        VStack(spacing: MosaicSpacing.xs) {
            NavigationLink(value: HomeRoute.ar) {
                HStack(spacing: MosaicSpacing.sm) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Launch AR")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MosaicSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(!device.canRunMosaic)

            if let reason = device.unsupportedReason {
                Text(reason)
                    .font(MosaicFont.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MosaicSpacing.sm)
            }
        }
        .padding(.horizontal, MosaicSpacing.lg)
        .padding(.top, MosaicSpacing.md)
        .padding(.bottom, MosaicSpacing.sm)
        .background(.bar)
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
