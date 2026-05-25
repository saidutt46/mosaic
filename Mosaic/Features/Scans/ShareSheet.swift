//
//  ShareSheet.swift
//  Mosaic
//
//  Thin SwiftUI wrapper over UIActivityViewController for sharing a
//  scan's files (USDZ / PLY) via AirDrop, Files, Messages, etc.
//  Present with `.sheet(item:)` using ShareItem.
//

import SwiftUI
import UIKit

/// Identifiable URL wrapper so a share target can drive `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
