import Foundation
import SwiftUI
import Testing

@testable import Uttrflow

/// The mark is drawn, so how it *looks* is not testable here. What is, and what would go
/// wrong silently, is its geometry: the mark is the one shape that appears at 16 points in
/// the menu bar and at 1024 in the Dock, and every one of those sizes is this path scaled.
/// A mark that drifts off its own proportions, loses the difference between its two stems,
/// or grows past the box the clear-space rule is measured from is a bug that ships as a
/// slightly wrong logo everywhere at once.
@Suite("The mark's geometry")
struct UttrflowMarkTests {
    /// The bounds of what is actually drawn.
    ///
    /// Not `path(in:).boundingRect`: the path is a centreline, so its box is a whole
    /// stroke narrower and shorter than the mark — and it is the stroked box that the
    /// proportions and the clear-space rule are stated in.
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

    /// 62:72 is the drawn box, not the 100×100 grid it is authored on. Anything that reads
    /// the grid as the shape puts the mark in a square and leaves it swimming.
    @Test("keeps the drawn box at its own proportions, not the grid's")
    func aspectRatio() {
        let box = drawn(UttrflowMark())

        #expect(abs(box.width / box.height - UttrflowMark.aspectRatio) < 0.005)
        #expect(abs(UttrflowMark.aspectRatio - 62.0 / 72.0) < 0.000_001)
    }

    /// The whole idea of the mark: a *u* whose stems are different heights, so it reads as
    /// a waveform as well as a letter. Equal stems would just be a horseshoe.
    @Test("draws the right stem taller than the left")
    func stemsDiffer() {
        let mark = UttrflowMark()

        #expect(mark.rightTop < mark.leftTop, "smaller y is taller")
        #expect(mark.leftTop - mark.rightTop >= 12, "too close and the difference stops reading")
    }

    /// Scaling happens on the shorter side, so the mark keeps its shape in a frame of any
    /// proportion rather than stretching to fill it.
    @Test("never stretches to fill a frame that is the wrong shape")
    func doesNotStretch() {
        let wide = drawn(UttrflowMark(), in: CGRect(x: 0, y: 0, width: 900, height: 300))
        let tall = drawn(UttrflowMark(), in: CGRect(x: 0, y: 0, width: 300, height: 900))

        #expect(abs(wide.width / wide.height - UttrflowMark.aspectRatio) < 0.005)
        #expect(abs(tall.width / tall.height - UttrflowMark.aspectRatio) < 0.005)
    }

    /// The stroke is half the story: the path is a centreline, and the round cap adds half
    /// a stroke width beyond every end. Clear space is measured from one stroke width, so a
    /// weight that stops tracking the height silently changes the spacing rule too.
    @Test("scales the stroke with the height")
    func strokeTracksHeight() {
        #expect(abs(UttrflowMark.lineWidth(forHeight: 72) - 14) < 0.000_001)
        #expect(abs(UttrflowMark.lineWidth(forHeight: 36) - 7) < 0.000_001)
        #expect(abs(UttrflowMark.lineWidth(forHeight: 16) - 16 / 72 * 14) < 0.000_001)
    }

    /// The animated listening state moves the stem tops. It must not move them so far that
    /// the round cap leaves the box the icon is exported from, where it is sliced flat —
    /// which is exactly what the first version of that animation did.
    @Test("keeps a raised stem inside the drawn box")
    func raisedStemStaysInside() {
        let resting = drawn(UttrflowMark())
        // y = 21 is the ceiling: the resting right stem, and the top of the drawn box.
        let raised = drawn(UttrflowMark(leftTop: 21, rightTop: 21))

        #expect(raised.minY >= resting.minY - 0.5)
        // And a stem driven above it does leave the box — which is the thing to avoid.
        #expect(drawn(UttrflowMark(leftTop: 21, rightTop: 17)).minY < resting.minY - 0.5)
    }

    /// `animatableData` is what lets SwiftUI interpolate the stems. Reading a value back
    /// that does not match what was written would animate to the wrong pose.
    @Test("round-trips both stems through the animatable pair")
    func animatableRoundTrip() {
        var mark = UttrflowMark()
        mark.animatableData = AnimatablePair(30, 25)

        #expect(mark.leftTop == 30)
        #expect(mark.rightTop == 25)
        #expect(mark.animatableData == AnimatablePair(30, 25))
    }
}
