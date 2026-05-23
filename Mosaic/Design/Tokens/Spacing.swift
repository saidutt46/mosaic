//
//  Spacing.swift
//  Mosaic
//
//  4pt-base spacing scale + semantic constants.
//  Prefer the semantic names (screenEdge, cardPadding) at use sites;
//  fall back to the scale (xs..xxxl) for ad-hoc gaps.
//

import CoreGraphics

enum MosaicSpacing {
    // MARK: Scale (4pt grid)
    static let xxs:  CGFloat = 2
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
    static let xxxl: CGFloat = 48

    // MARK: Semantic
    static let screenEdge:  CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let rowMin:      CGFloat = 44  // Apple HIG min hit target
    static let hudInset:    CGFloat = 12
}
