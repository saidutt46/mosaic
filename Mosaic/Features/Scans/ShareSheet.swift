//
//  ShareSheet.swift
//  Mosaic
//
//  Thin SwiftUI wrapper over UIActivityViewController for sharing a
//  scan's files (USDZ / PLY). Present with `.sheet(item:)` using
//  ShareItem. Share targets show a human filename (the scan's name)
//  rather than the on-disk "mesh.usdz" — see ShareFile.prepared.
//

import SwiftUI
import UIKit

/// Identifiable URL wrapper so a share target can drive `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum ShareFile {
    /// Copy `source` into tmp under the scan's display name so the share
    /// sheet shows e.g. "Scan_2026-05-24_18-55.usdz" instead of the
    /// on-disk "mesh.usdz". Returns the temp URL to share (cleaned up by
    /// ShareSheet on completion).
    static func prepared(from source: URL, named name: String) -> URL? {
        let safe = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
            .appendingPathExtension(source.pathExtension)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Remove any temp copies we prepared just for sharing.
            let tmp = FileManager.default.temporaryDirectory.path
            for case let url as URL in items where url.path.hasPrefix(tmp) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
