// Tests for the mark's geometry.

import Foundation
import SwiftUI
import Testing

@testable import Uttrflow

/// The mark's geometry is testable: one path scaled from 16 points to 1024, so drift ships everywhere.
@Suite("The mark's geometry")
struct UttrflowMarkTests {
    /// The bounds of what is drawn: the stroked box, not the centreline path's.
    private func drawn(_ mark: UttrflowMark, in rect: CGRect) -> CGRect {
        let scale = min(
            rect.width / UttrflowMark.gridBox.width,
            rect.height / UttrflowMark.gridBox.height)
        return
            mark
            .path(in: rect)
            .strokedPath(
                StrokeStyle(
                    lineWidth: UttrflowMark.strokeUnits * scale,
                    lineCap: .round, lineJoin: .round)
            )
            .boundingRect
    }

    private func drawn(_ mark: UttrflowMark, in side: CGFloat = 720) -> CGRect {
        drawn(mark, in: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// 62:72 is the drawn box, not the 100×100 grid; reading the grid as the shape leaves the mark swimming.
    @Test("keeps the drawn box at its own proportions, not the grid's")
    func aspectRatio() {
        let box = drawn(UttrflowMark())

        #expect(abs(box.width / box.height - UttrflowMark.aspectRatio) < 0.005)
        #expect(abs(UttrflowMark.aspectRatio - 62.0 / 72.0) < 0.000_001)
    }

    /// A *u* whose stems differ in height reads as a waveform as well as a letter.
    @Test("draws the right stem taller than the left")
    func stemsDiffer() {
        let mark = UttrflowMark()

        #expect(mark.rightTop < mark.leftTop, "smaller y is taller")
        #expect(mark.leftTop - mark.rightTop >= 12, "too close and the difference stops reading")
    }

    /// Scaling happens on the shorter side, so the mark keeps its shape in any frame.
    @Test("never stretches to fill a frame that is the wrong shape")
    func doesNotStretch() {
        let wide = drawn(UttrflowMark(), in: CGRect(x: 0, y: 0, width: 900, height: 300))
        let tall = drawn(UttrflowMark(), in: CGRect(x: 0, y: 0, width: 300, height: 900))

        #expect(abs(wide.width / wide.height - UttrflowMark.aspectRatio) < 0.005)
        #expect(abs(tall.width / tall.height - UttrflowMark.aspectRatio) < 0.005)
    }

    /// The round cap adds half a stroke beyond every end, and clear space is measured in strokes.
    @Test("scales the stroke with the height")
    func strokeTracksHeight() {
        #expect(abs(UttrflowMark.lineWidth(forHeight: 72) - 14) < 0.000_001)
        #expect(abs(UttrflowMark.lineWidth(forHeight: 36) - 7) < 0.000_001)
        #expect(abs(UttrflowMark.lineWidth(forHeight: 16) - 16 / 72 * 14) < 0.000_001)
    }

    /// A raised stem must not leave the box the icon is exported from, where it is sliced flat.
    @Test("keeps a raised stem inside the drawn box")
    func raisedStemStaysInside() {
        let resting = drawn(UttrflowMark())
        // y = 21 is the ceiling: the resting right stem, and the top of the drawn box.
        let raised = drawn(UttrflowMark(leftTop: 21, rightTop: 21))

        #expect(raised.minY >= resting.minY - 0.5)
        // And a stem driven above it does leave the box — which is the thing to avoid.
        #expect(drawn(UttrflowMark(leftTop: 21, rightTop: 17)).minY < resting.minY - 0.5)
    }

    /// `animatableData` must read back what was written, or SwiftUI animates to the wrong pose.
    @Test("round-trips both stems through the animatable pair")
    func animatableRoundTrip() {
        var mark = UttrflowMark()
        mark.animatableData = AnimatablePair(30, 25)

        #expect(mark.leftTop == 30)
        #expect(mark.rightTop == 25)
        #expect(mark.animatableData == AnimatablePair(30, 25))
    }
}
