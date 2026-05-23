//
//  ContentView.swift
//  Mosaic
//
//  Temporary root view: shows the DesignGallery wrapped in a
//  NavigationStack with a Settings entry point. Replaced by the
//  Home view in Phase 4.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            DesignGallery()
                .navigationTitle("Mosaic")
                .navigationBarTitleDisplayMode(.inline)
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
}

#Preview {
    ContentView()
        .environment(AppSettings())
}
