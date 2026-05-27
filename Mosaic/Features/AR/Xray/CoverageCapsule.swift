//
//  CoverageCapsule.swift
//  Mosaic
//
//  Compact glass HUD pill for the coverage mode (F.2.3): shows the live
//  "% covered" from the CaptureCoach engine, tinted red→green by the
//  same ramp as the mesh. Shown only while coverage is on screen.
//  Actionable guidance (arrows / "scan toward X") is a later step — this
//  is just the glanceable number.
//

import SwiftUI

struct CoverageCapsule: View {

    let report: CoverageReport

    var body: some View {
        HStack(spacing: MosaicSpacing.xs) {
            Image(systemName: "viewfinder")
                .font(.system(size: 11, weight: .semibold))
            content
        }
        // Camera-app text: white + double shadow so it reads over any
        // backdrop; the glass capsule sits behind it.
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 2)
        .padding(.horizontal, MosaicSpacing.sm)
        .padding(.vertical, MosaicSpacing.xs)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var content: some View {
        switch report.guidance {
        case .insufficientData:
            Text("Scanning…")
                .font(.system(size: 12, weight: .medium))
        default:
            HStack(spacing: 2) {
                Text("\(percent)%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("covered")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.85)
            }
        }
    }

    private var percent: Int {
        Int((report.coverageFraction * 100).rounded())
    }

    private var accessibilityDescription: String {
        switch report.guidance {
        case .insufficientData: "Scanning for coverage"
        default:                "\(percent) percent covered"
        }
    }
}
