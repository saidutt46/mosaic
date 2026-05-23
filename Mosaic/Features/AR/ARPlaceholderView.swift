//
//  ARPlaceholderView.swift
//  Mosaic
//
//  Stand-in for the real AR view — replaced in Phase 5 by an ARKit
//  session that streams classification labels into the logger.
//

import SwiftUI

struct ARPlaceholderView: View {
    var body: some View {
        VStack(spacing: MosaicSpacing.lg) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(MosaicColor.hudCyan)
            Text("AR view coming in Phase 5")
                .font(MosaicFont.title2)
            Text("ARKit session + classification logging next, then Metal in Phase 6.")
                .font(MosaicFont.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(MosaicSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MosaicColor.background.ignoresSafeArea())
        .navigationTitle("AR")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { ARPlaceholderView() }
}
