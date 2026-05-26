//
//  AppServices.swift
//  Mosaic
//
//  Composition root for app-lifetime services. Created once in
//  MosaicApp and injected via `.environment` — views read it with
//  `@Environment(AppServices.self)`. Members are constructor-injected,
//  so when a service grows a dependency on another it's wired here,
//  explicitly, rather than resolved from a global locator.
//
//  Each member is itself @Observable, so views observe `services.x.y`
//  normally. Keep this small; it's a typed container, not a registry.
//

import Observation

@Observable
@MainActor
final class AppServices {
    let settings: AppSettings
    let scans: ScanRepository

    /// Designated init — pass dependencies explicitly (tests / previews).
    init(settings: AppSettings, scans: ScanRepository) {
        self.settings = settings
        self.scans = scans
    }

    /// App default — builds the standard services.
    convenience init() {
        self.init(settings: AppSettings(), scans: ScanRepository())
    }
}
