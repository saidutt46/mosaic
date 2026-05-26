//
//  MosaicApp.swift
//  Mosaic
//

import SwiftUI
import os

@main
struct MosaicApp: App {
    @State private var services = AppServices()

    init() {
        Log.app.info("Mosaic launched · v\(AboutInfo.versionString, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(services)
                .preferredColorScheme(services.settings.appearance.colorScheme)
        }
    }
}
