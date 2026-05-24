//
//  HomeView.swift
//  Mosaic
//
//  Time-of-day greeting + 2×2 grid of quick-action tiles. Today
//  only "Filters" (Track A) is live; the rest are placeholders
//  reserved for Track B and beyond.
//
//  Toolbar: trailing info button (opens a System Info sheet with
//  the device/capabilities/sensor dump) + gear (Settings).
//

import SwiftUI

private enum HomeRoute: Hashable {
    case filters
    case xray
}

struct HomeView: View {
    @State private var monitor = DeviceMonitor()
    @State private var showingSystemInfo = false
    private let device = DeviceInfo.current()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MosaicSpacing.xxl) {
                    greetingHeader
                        .padding(.top, MosaicSpacing.sm)

                    quickActionsGrid

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MosaicSpacing.lg)
                .padding(.bottom, MosaicSpacing.xl)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .filters: FiltersView()
                case .xray:    XrayView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSystemInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSystemInfo) {
                SystemInfoSheet(device: device, monitor: monitor)
            }
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hello,")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.primary)
            Text(timeGreeting)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return switch hour {
        case 5..<12:  "Good morning."
        case 12..<17: "Good afternoon."
        case 17..<22: "Good evening."
        default:      "Good night."
        }
    }

    // MARK: - Quick actions grid

    private var quickActionsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: MosaicSpacing.md),
                GridItem(.flexible(), spacing: MosaicSpacing.md),
            ],
            spacing: MosaicSpacing.md
        ) {
            QuickActionTile(
                title: "Filters",
                subtitle: "Camera effects",
                icon: "camera.filters",
                tint: .blue,
                state: device.canRunMosaic ? .available : .unavailable("LiDAR"),
                destination: .filters
            )
            QuickActionTile(
                title: "X-Ray",
                subtitle: "Classified mesh",
                icon: "cube.transparent.fill",
                tint: .purple,
                state: device.canRunMosaic ? .available : .unavailable("LiDAR"),
                destination: .xray
            )
            QuickActionTile(
                title: "Detect",
                subtitle: "Object recognition",
                icon: "dot.viewfinder",
                tint: .green,
                state: .unavailable("Soon"),
                destination: nil
            )
            QuickActionTile(
                title: "Capture",
                subtitle: "Scene reconstruction",
                icon: "video.fill",
                tint: .orange,
                state: .unavailable("Soon"),
                destination: nil
            )
        }
    }
}

// MARK: - Quick action tile

private struct QuickActionTile: View {
    enum State {
        case available
        case unavailable(String)  // label shown in the badge

        var isAvailable: Bool {
            if case .available = self { return true } else { return false }
        }

        var badge: String? {
            if case .unavailable(let label) = self { return label } else { return nil }
        }
    }

    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let state: State
    let destination: HomeRoute?

    var body: some View {
        if let destination, state.isAvailable {
            NavigationLink(value: destination) { tileContent }
                .buttonStyle(TilePressStyle())
        } else {
            tileContent
                .opacity(0.55)
        }
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: MosaicSpacing.md) {
            iconChip
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .opacity(0.7)
            }
        }
        .padding(MosaicSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 170)
        .background(
            tint.opacity(0.18),
            in: RoundedRectangle(cornerRadius: MosaicRadius.xl,
                                 style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            if let badge = state.badge {
                Text(badge.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .padding(.horizontal, MosaicSpacing.sm)
                    .padding(.vertical, MosaicSpacing.xxs + 2)
                    .background(.regularMaterial, in: Capsule())
                    .padding(MosaicSpacing.md)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var iconChip: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 48, height: 48)
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - System info sheet

private struct SystemInfoSheet: View {
    let device: DeviceInfo
    let monitor: DeviceMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    infoRow("Model",  device.modelIdentifier,
                            icon: "iphone")
                    infoRow("System", "\(device.systemName) \(device.systemVersion)",
                            icon: "apple.logo")
                    infoRow("Memory", String(format: "%.1f GB", device.physicalMemoryGB),
                            icon: "memorychip")
                    infoRow("Cores",  "\(device.processorCount)",
                            icon: "cpu")
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
            .navigationTitle("System Info")
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

// MARK: - Row helpers (used in the sheet)

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

// MARK: - Previews

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
