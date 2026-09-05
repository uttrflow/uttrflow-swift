// The mark stroked at a given height.

import SwiftUI

/// The mark at a given height, stroked at its own weight, in the foreground style; never the accent.
struct UttrflowMarkView: View {
    var height: CGFloat = 22

    var body: some View {
        UttrflowMark()
            .stroke(
                style: StrokeStyle(
                    lineWidth: UttrflowMark.lineWidth(forHeight: height),
                    lineCap: .round, lineJoin: .round)
            )
            .frame(width: height * UttrflowMark.aspectRatio, height: height)
            .accessibilityHidden(true)
    }
}
