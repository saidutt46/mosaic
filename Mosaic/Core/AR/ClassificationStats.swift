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
import Metal

@MainActor
final class ClassificationStats {

    private struct Entry {
        var faceCount: Int
        var classCounts: [ARMeshClassification: Int]
    }

    private var perAnchor: [UUID: Entry] = [:]

    var anchorCount: Int { perAnchor.count }

    func update(from anchor: ARMeshAnchor) {
        perAnchor[anchor.identifier] = Self.tally(anchor)
    }

    func remove(_ anchor: ARMeshAnchor) {
        perAnchor.removeValue(forKey: anchor.identifier)
    }

    func reset() {
        perAnchor.removeAll()
    }

    /// One-line summary suitable for Log.ar.info, e.g.
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
            .map { "\(Self.label($0.key)):\($0.value)" }
        return "anchors=\(perAnchor.count) faces=\(totalFaces) \(parts.joined(separator: " "))"
    }

    // MARK: - Helpers

    private static func tally(_ anchor: ARMeshAnchor) -> Entry {
        let geom = anchor.geometry
        let faceCount = geom.faces.count
        var classCounts: [ARMeshClassification: Int] = [:]

        if let classBuffer = geom.classification {
            // One UInt8 per face — value is the ARMeshClassification raw value.
            let ptr = classBuffer.buffer.contents()
                .advanced(by: classBuffer.offset)
                .bindMemory(to: UInt8.self, capacity: faceCount)
            for i in 0..<faceCount {
                if let kind = ARMeshClassification(rawValue: Int(ptr[i])) {
                    classCounts[kind, default: 0] += 1
                }
            }
        }
        return Entry(faceCount: faceCount, classCounts: classCounts)
    }

    static func label(_ c: ARMeshClassification) -> String {
        switch c {
        case .none:     "none"
        case .wall:     "wall"
        case .floor:    "floor"
        case .ceiling:  "ceiling"
        case .table:    "table"
        case .seat:     "seat"
        case .window:   "window"
        case .door:     "door"
        @unknown default: "?"
        }
    }
}
