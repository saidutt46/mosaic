//
//  DeviceInfo.swift
//  Mosaic
//
//  One-shot device capability snapshot + live system-state monitor.
//  DeviceInfo answers "what does this device support?" — checked at
//  Home view render. DeviceMonitor publishes live thermal/power state.
//

import Foundation
import SwiftUI
import UIKit
import ARKit
import AVFoundation
import CoreMotion
import Observation
import Combine

// MARK: - Static capability snapshot

struct DeviceInfo {
    // Identity
    let modelIdentifier: String      // e.g. "iPhone17,2"
    let systemName: String           // "iOS"
    let systemVersion: String        // "26.5"
    let physicalMemoryGB: Double
    let processorCount: Int

    // AR capabilities
    let worldTrackingSupported: Bool
    let sceneReconstructionSupported: Bool   // .meshWithClassification — the gate
    let sceneDepthSupported: Bool            // LiDAR proxy

    // Sensors
    let backCameraAvailable: Bool
    let motionAvailable: Bool

    static func current() -> DeviceInfo {
        DeviceInfo(
            modelIdentifier: hwModel(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            physicalMemoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
            processorCount: ProcessInfo.processInfo.processorCount,
            worldTrackingSupported: ARWorldTrackingConfiguration.isSupported,
            sceneReconstructionSupported: ARWorldTrackingConfiguration
                .supportsSceneReconstruction(.meshWithClassification),
            sceneDepthSupported: ARWorldTrackingConfiguration
                .supportsFrameSemantics(.sceneDepth),
            backCameraAvailable: AVCaptureDevice
                .default(.builtInWideAngleCamera, for: .video, position: .back) != nil,
            motionAvailable: CMMotionManager().isDeviceMotionAvailable
        )
    }

    /// Mosaic's AR experience requires classified scene reconstruction (LiDAR).
    var canRunMosaic: Bool { sceneReconstructionSupported }

    var unsupportedReason: String? {
        guard !canRunMosaic else { return nil }
        if !worldTrackingSupported {
            return "ARKit world tracking is not supported on this device."
        }
        if !sceneDepthSupported {
            return "Mosaic requires a LiDAR scanner. This device does not have one."
        }
        return "Classified scene reconstruction is not supported on this device."
    }

    // MARK: Helpers

    private static func hwModel() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
    }
}

// MARK: - Live system state

@Observable
final class DeviceMonitor {
    var thermalState: ProcessInfo.ThermalState
    var lowPowerMode: Bool

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init() {
        let info = ProcessInfo.processInfo
        self.thermalState = info.thermalState
        self.lowPowerMode = info.isLowPowerModeEnabled

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.thermalState = ProcessInfo.processInfo.thermalState }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
            .store(in: &cancellables)
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal:  "Nominal"
        case .fair:     "Fair"
        case .serious:  "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    var tintColor: Color {
        switch self {
        case .nominal:  .green
        case .fair:     .yellow
        case .serious:  .orange
        case .critical: .red
        @unknown default: .gray
        }
    }
}
