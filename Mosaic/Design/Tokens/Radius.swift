//
//  Radius.swift
//  Mosaic
//
//  Corner radius scale. Pair with `.continuous` rect style at call sites.
//

import CoreGraphics

enum MosaicRadius {
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 24
    static let pill: CGFloat = 1000  // fully rounded for capsules
}
