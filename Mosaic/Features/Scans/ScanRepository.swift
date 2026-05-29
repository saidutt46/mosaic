//
//  ScanRepository.swift
//  Mosaic
//
//  Single entry point for saved-scan CRUD. Scans live one-folder-each
//  under Documents/Scans/; the catalog is the filesystem itself (no
//  Core Data). Listing enumerates the directory and decodes each
//  manifest.json. Saving stages into a "<UUID>.writing" directory and
//  renames into place once every artifact is written, so a crash mid-
//  save can never leave a half-formed scan — only an orphan staging
//  dir, which `reload()` sweeps.
//
//  USDZ export (E.1.1) and thumbnail capture (E.1.3) attach to the
//  save flow at the marked points below.
//

import Foundation
import UIKit
import Observation
import os

@Observable @MainActor
final class ScanRepository {

    private(set) var scans: [Scan] = []

    private let fileManager = FileManager.default

    // MARK: - Listing

    /// Sweep orphaned staging dirs, then load every completed scan,
    /// newest first. Cheap to call repeatedly (10s–100s of scans).
    func reload() async {
        ensureScansDirectory()
        sweepWritingDirectories()

        let contents = (try? fileManager.contentsOfDirectory(
            at: DocumentsURL.scansDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [Scan] = []
        for dir in contents where dir.hasDirectoryPath && !DocumentsURL.isWritingDirectory(dir) {
            let manifestURL = dir.appendingPathComponent(ScanArtifact.manifest.filename)
            guard let data = try? Data(contentsOf: manifestURL),
                  let scan = try? Self.decoder.decode(Scan.self, from: data) else {
                Log.app.warning("scan listing: skipping \(dir.lastPathComponent, privacy: .public) — no readable manifest")
                continue
            }
            loaded.append(scan)
        }

        scans = loaded.sorted { $0.createdAt > $1.createdAt }
        Log.app.info("scan listing: \(self.scans.count) scan(s) loaded")
    }

    // MARK: - Save

    /// Persist a snapshot of the current mesh as a new scan. The heavy
    /// serialization (USDZ in E.1.1) runs off the main actor; only the
    /// final `scans` mutation hops back here.
    @discardableResult
    func save(snapshot: [MeshAnchorBuffers],
              stats: (anchors: Int, faces: Int, vertices: Int),
              palette: [SIMD4<Float>] = MeshOverlayPass.defaultPalette,
              coverage: CoverageSnapshot? = nil,
              thumbnail: UIImage?) async throws -> Scan {
        ensureScansDirectory()

        let id = UUID()
        let createdAt = Date()
        let writingDir = DocumentsURL.writingScanDirectory(id: id)
        let finalDir = DocumentsURL.scanDirectory(id: id)

        // Stage everything in the .writing dir, then rename atomically.
        try fileManager.createDirectory(at: writingDir, withIntermediateDirectories: true)

        do {
            var artifacts: [ScanArtifact] = [.manifest]

            // USDZ (shareable mesh) + PLY (semantic point cloud) — both
            // CPU-bound; run off the main actor. The snapshot's buffers
            // are immutable shared-storage (MeshAnchorBuffers is
            // Sendable), so reading them from a detached task is safe.
            let usdzURL = writingDir.appendingPathComponent(ScanArtifact.usdz.filename)
            let plyURL = writingDir.appendingPathComponent(ScanArtifact.pointCloud.filename)
            // coverage.ply is optional — only written when the coach
            // actually accumulated data this session (ingest is gated to
            // coverage mode on screen).
            let coverageURL = writingDir.appendingPathComponent(ScanArtifact.coverage.filename)
            let coverageToWrite: CoverageSnapshot? = (coverage?.isEmpty == false) ? coverage : nil

            try await Task.detached(priority: .userInitiated) {
                try USDZExporter.write(snapshot: snapshot, palette: palette, to: usdzURL)
                try PLYExporter.write(snapshot: snapshot, palette: palette, to: plyURL)
                if let coverageToWrite {
                    try CoveragePLYExporter.write(snapshot: coverageToWrite, to: coverageURL)
                }
            }.value
            artifacts.append(.usdz)
            artifacts.append(.pointCloud)
            if coverageToWrite != nil { artifacts.append(.coverage) }

            if let thumbnail, let jpeg = thumbnail.jpegData(compressionQuality: 0.8) {
                try jpeg.write(to: writingDir.appendingPathComponent(ScanArtifact.thumbnail.filename))
                artifacts.append(.thumbnail)
            }

            let scan = Scan(
                id: id,
                name: Scan.autoName(for: createdAt),
                createdAt: createdAt,
                anchorCount: stats.anchors,
                faceCount: stats.faces,
                vertexCount: stats.vertices,
                artifacts: artifacts
            )

            // Manifest written last — its presence marks the scan complete.
            let manifestData = try Self.encoder.encode(scan)
            try manifestData.write(to: writingDir.appendingPathComponent(ScanArtifact.manifest.filename))

            if fileManager.fileExists(atPath: finalDir.path) {
                try fileManager.removeItem(at: finalDir)
            }
            try fileManager.moveItem(at: writingDir, to: finalDir)

            scans.insert(scan, at: 0)
            Log.app.info("scan saved: \(id.uuidString.prefix(8), privacy: .public) faces=\(stats.faces)")
            return scan
        } catch {
            try? fileManager.removeItem(at: writingDir)
            Log.app.error("scan save failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Rename

    /// Update a scan's display name — rewrites manifest.json and the
    /// in-memory model so the change reflects everywhere sharing this repo.
    func rename(_ id: UUID, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = scans.firstIndex(where: { $0.id == id }) else { return }

        var scan = scans[index]
        scan.name = trimmed
        let manifestURL = DocumentsURL.artifactURL(scanID: id, .manifest)
        let data = try Self.encoder.encode(scan)
        try data.write(to: manifestURL)
        scans[index] = scan
        Log.app.info("scan renamed: \(id.uuidString.prefix(8), privacy: .public)")
    }

    // MARK: - Delete

    func delete(_ id: UUID) async throws {
        let dir = DocumentsURL.scanDirectory(id: id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        scans.removeAll { $0.id == id }
        Log.app.info("scan deleted: \(id.uuidString.prefix(8), privacy: .public)")
    }

    /// URL of an artifact if it exists on disk, else nil. For share /
    /// QuickLook hand-off in later phases.
    func openURL(for scanID: UUID, artifact: ScanArtifact) -> URL? {
        let url = DocumentsURL.artifactURL(scanID: scanID, artifact)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Internals

    private func ensureScansDirectory() {
        try? fileManager.createDirectory(at: DocumentsURL.scansDirectory, withIntermediateDirectories: true)
    }

    private func sweepWritingDirectories() {
        let contents = (try? fileManager.contentsOfDirectory(
            at: DocumentsURL.scansDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for dir in contents where DocumentsURL.isWritingDirectory(dir) {
            try? fileManager.removeItem(at: dir)
            Log.app.info("scan sweep: removed orphan \(dir.lastPathComponent, privacy: .public)")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
