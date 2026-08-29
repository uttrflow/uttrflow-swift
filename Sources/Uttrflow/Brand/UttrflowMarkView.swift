import SwiftUI

/// The mark at a given height, stroked at its own weight.
///
/// Takes its colour from the foreground style, because the mark has no colour of its
/// own: it is ink on light and chalk on dark, and never the accent — the accent means a
/// state, and a logo is not a state.
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
