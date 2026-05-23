//
//  Log.swift
//  Mosaic
//
//  Unified logging facade over Apple's os.Logger. Categories are
//  fixed so log lines stay greppable in Console.app and Xcode.
//
//  Usage:
//      Log.ar.info("session started")
//      Log.metal.error("failed to compile pipeline: \(error)")
//      Log.perf.debug("frame=\(ms, format: .fixed(precision: 2))ms")
//
//  Notes:
//  - os.Logger handles privacy redaction automatically. Mark
//    user-visible strings with `\(value, privacy: .public)` when you
//    want them to appear in release logs.
//  - Categories double as filters in Console.app — keep names short.
//

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.daivatcreations.Mosaic"

    static let app      = Logger(subsystem: subsystem, category: "app")
    static let ar       = Logger(subsystem: subsystem, category: "ar")
    static let render   = Logger(subsystem: subsystem, category: "render")
    static let metal    = Logger(subsystem: subsystem, category: "metal")
    static let ui       = Logger(subsystem: subsystem, category: "ui")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let perf     = Logger(subsystem: subsystem, category: "perf")
}
