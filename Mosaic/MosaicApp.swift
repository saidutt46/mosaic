//
//  MosaicApp.swift
//  Mosaic
//

import SwiftUI
import os

@main
struct MosaicApp: App {
    @State private var settings = AppSettings()

    init() {
        Log.app.info("Mosaic launched · v\(AboutInfo.versionString, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
