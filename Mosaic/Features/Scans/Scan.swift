//
//  Scan.swift
//  Mosaic
//
//  Value model for one saved X-Ray scan plus the set of artifact
//  files that can live in its directory. `manifest.json` holds an
//  encoded Scan and is the source of truth: it is written last on
//  save and read first on listing, so its presence means "complete".
//

import Foundation

// MARK: - Scan

struct Scan: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String                    // e.g. "Scan 2026-05-24 10:42"
    let createdAt: Date

    // Mesh stats captured at snapshot time — for library display.
    let anchorCount: Int
    let faceCount: Int
    let vertexCount: Int

    // Which artifacts exist in this scan's directory.
    var artifacts: [ScanArtifact]

    /// Default auto-name from a creation date. Renamed later (post-v1).
    static func autoName(for date: Date) -> String {
        "Scan " + autoNameFormatter.string(from: date)
    }

    private static let autoNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

// MARK: - ScanArtifact

enum ScanArtifact: String, Codable, CaseIterable {
    case manifest      // manifest.json — always present
    case usdz          // mesh.usdz
    case thumbnail     // thumbnail.jpg
    case meshJSON      // mesh.json
    case pointCloud    // pointcloud.ply

    var filename: String {
        switch self {
        case .manifest:   "manifest.json"
        case .usdz:       "mesh.usdz"
        case .thumbnail:  "thumbnail.jpg"
        case .meshJSON:   "mesh.json"
        case .pointCloud: "pointcloud.ply"
        }
    }
}
