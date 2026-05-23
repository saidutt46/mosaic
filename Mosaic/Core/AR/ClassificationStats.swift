//
//  ClassificationStats.swift
//  Mosaic
//
//  Per-anchor classification tally. Updated incrementally from
//  ARMeshAnchor adds/updates/removes; summarized periodically by
//  ARSessionManager for the rolling log line.
//

import Foundation
import ARKit

@MainActor
final class ClassificationStats {

    private struct Entry {
        var faceCount: Int
        var classCounts: [ARMeshClassification: Int]
    }

    private var perAnchor: [UUID: Entry] = [:]

    var anchorCount: Int { perAnchor.count }

    func update(from anchor: ARMeshAnchor) {
        perAnchor[anchor.identifier] = tally(anchor)
    }

    func remove(_ anchor: ARMeshAnchor) {
        perAnchor.removeValue(forKey: anchor.identifier)
    }

    func reset() {
        perAnchor.removeAll()
    }

    /// One-line summary for Log.ar.info, e.g.
    /// `anchors=8 faces=12420 floor:4100 wall:3800 ceiling:1900 …`
    func summary() -> String {
        var totals: [ARMeshClassification: Int] = [:]
        var totalFaces = 0
        for entry in perAnchor.values {
            totalFaces += entry.faceCount
            for (k, v) in entry.classCounts { totals[k, default: 0] += v }
        }
        guard !totals.isEmpty else { return "" }
        let parts = totals
            .sorted { $0.value > $1.value }
            .map { "\($0.key.label):\($0.value)" }
        return "anchors=\(perAnchor.count) faces=\(totalFaces) \(parts.joined(separator: " "))"
    }

    // MARK: - Helpers

    private func tally(_ anchor: ARMeshAnchor) -> Entry {
        let geom = anchor.geometry
        let faceCount = geom.faces.count
        var counts: [ARMeshClassification: Int] = [:]
        for i in 0..<faceCount {
            counts[geom.classification(faceIndex: i), default: 0] += 1
        }
        return Entry(faceCount: faceCount, classCounts: counts)
    }
}
