//
//  Motion.swift
//  Mosaic
//
//  Animation presets. Use a named token rather than ad-hoc durations
//  so motion stays coherent across the app.
//

import SwiftUI

enum MosaicMotion {
    static let quick   = Animation.easeOut(duration: 0.15)
    static let snappy  = Animation.snappy(duration: 0.25)
    static let smooth  = Animation.smooth(duration: 0.35)
    static let bouncy  = Animation.bouncy(duration: 0.45)
}
