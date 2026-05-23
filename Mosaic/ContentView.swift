//
//  ContentView.swift
//  Mosaic
//
//  App root — currently just hosts HomeView. Kept as a thin wrapper
//  so future root concerns (deep links, app-state gating, onboarding)
//  have a place to land without touching MosaicApp directly.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
}
