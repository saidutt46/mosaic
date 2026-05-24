//
//  AppSettings.swift
//  Mosaic
//
//  Observable settings store. Single source of truth for user
//  preferences; persisted to UserDefaults on write. Injected via
//  @Environment(AppSettings.self) at the app root.
//

import SwiftUI
import Observation

// MARK: - Appearance

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max"
        case .dark:   "moon"
        }
    }

    /// SwiftUI override. `nil` lets the system decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

// MARK: - Store

@Observable
final class AppSettings {
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    // MARK: Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.appearance) ?? AppearanceMode.system.rawValue
        self.appearance = AppearanceMode(rawValue: raw) ?? .system
    }

    // MARK: Keys

    private enum Keys {
        static let appearance = "settings.appearance"
    }
}
