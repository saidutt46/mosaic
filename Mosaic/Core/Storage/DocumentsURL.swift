//
//  DocumentsURL.swift
//  Mosaic
//
//  Single source of truth for where saved scans live on disk.
//  Everything sits under Documents/Scans/ so scans are visible in
//  the Files app (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace).
//  A scan is written into a sibling "<UUID>.writing" directory and
//  renamed into place atomically once complete — see ScanRepository.
//

import Foundation

enum DocumentsURL {

    private static let scansFolderName = "Scans"
    private static let writingSuffix = ".writing"

    /// Documents/
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Documents/Scans/
    static var scansDirectory: URL {
        documents.appendingPathComponent(scansFolderName, isDirectory: true)
    }

    /// Documents/Scans/<UUID>/ — the final home of a completed scan.
    static func scanDirectory(id: UUID) -> URL {
        scansDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Documents/Scans/<UUID>.writing/ — the staging dir during a save.
    static func writingScanDirectory(id: UUID) -> URL {
        scansDirectory.appendingPathComponent(id.uuidString + writingSuffix, isDirectory: true)
    }

    /// Absolute URL of one artifact inside a completed scan's directory.
    static func artifactURL(scanID: UUID, _ artifact: ScanArtifact) -> URL {
        scanDirectory(id: scanID).appendingPathComponent(artifact.filename, isDirectory: false)
    }

    /// True for the staging directories left behind by an interrupted
    /// save. ScanRepository sweeps these on init.
    static func isWritingDirectory(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(writingSuffix)
    }
}
