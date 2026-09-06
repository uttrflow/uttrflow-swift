// Tests for resizing the panel: which border, the flip, the bands, drags, the floor, and the screen.
import Foundation
import Testing

@testable import UttrflowUX

/// Dragging the panel's border, with every expectation in AppKit's bottom-left coordinates.
@Suite("Resizing the quick panel")
struct PanelResizeTests {
    /// The design's size, at the top-right of a 1440×900 screen.
    static let frame = CGRect(x: 1008, y: 328, width: 420, height: 560)
    /// The usable screen below the menu bar.
    static let visible = CGRect(x: 0, y: 0, width: 1440, height: 860)

    /// The frame after a drag of this edge.
    private func resized(
        _ edge: PanelEdge, by delta: CGSize, from frame: CGRect = PanelResizeTests.frame,
        within visible: CGRect? = nil
    ) -> CGRect {
        PanelResize.resized(frame, dragging: edge, by: delta, within: visible)
    }

    // MARK: - Which border the pointer is on

    @Test("the middle of the panel is not a border, and keeps its clicks")
    func theMiddleIsNotABorder() {
        let size = CGSize(width: 420, height: 560)

        #expect(PanelResize.edge(at: CGPoint(x: 210, y: 280), in: size) == nil)
        #expect(PanelResize.edge(at: CGPoint(x: 12, y: 280), in: size) == nil)
    }

    @Test("each border answers as itself")
    func eachBorder() {
        let size = CGSize(width: 420, height: 560)

        #expect(PanelResize.edge(at: CGPoint(x: 2, y: 280), in: size) == .left)
        #expect(PanelResize.edge(at: CGPoint(x: 418, y: 280), in: size) == .right)
        #expect(PanelResize.edge(at: CGPoint(x: 210, y: 558), in: size) == .top)
        #expect(PanelResize.edge(at: CGPoint(x: 210, y: 2), in: size) == .bottom)
    }

    /// A corner resolving to the nearer edge would swap under the pointer mid-diagonal-drag.
    @Test("and a corner answers as a corner, not as the nearer edge")
    func corners() {
        let size = CGSize(width: 420, height: 560)

        #expect(PanelResize.edge(at: CGPoint(x: 1, y: 1), in: size) == .bottomLeft)
        #expect(PanelResize.edge(at: CGPoint(x: 419, y: 1), in: size) == .bottomRight)
        #expect(PanelResize.edge(at: CGPoint(x: 1, y: 559), in: size) == .topLeft)
        #expect(PanelResize.edge(at: CGPoint(x: 419, y: 559), in: size) == .topRight)
    }

    /// A point beyond the border belongs to whatever is behind the panel.
    @Test("a point outside the panel is on no border at all")
    func outsideIsNothing() {
        let size = CGSize(width: 420, height: 560)

        #expect(PanelResize.edge(at: CGPoint(x: -2, y: 280), in: size) == nil)
        #expect(PanelResize.edge(at: CGPoint(x: 210, y: 570), in: size) == nil)
    }

    // MARK: - Which way up the view is

    /// A flipped view's small `y` is its top; reading it as the bottom made the panel shrink when pulled.
    @Test("a flipped view's top is the top, not the bottom")
    func flippedIsUndone() {
        let size = CGSize(width: 420, height: 560)

        // Small y: the top of a flipped view, the bottom of an upright one.
        #expect(PanelResize.edge(at: CGPoint(x: 210, y: 2), in: size, isFlipped: true) == .top)
        #expect(PanelResize.edge(at: CGPoint(x: 210, y: 2), in: size, isFlipped: false) == .bottom)

        #expect(
            PanelResize.edge(at: CGPoint(x: 210, y: 558), in: size, isFlipped: true) == .bottom)
        #expect(
            PanelResize.edge(at: CGPoint(x: 210, y: 558), in: size, isFlipped: false) == .top)
    }

    @Test("and its corners follow the same way up")
    func flippedCorners() {
        let size = CGSize(width: 420, height: 560)

        #expect(PanelResize.edge(at: CGPoint(x: 1, y: 1), in: size, isFlipped: true) == .topLeft)
        #expect(
            PanelResize.edge(at: CGPoint(x: 419, y: 559), in: size, isFlipped: true)
                == .bottomRight)
    }

    /// A flip never touches `x`, which is why the bug survived being tried by hand on the sides.
    @Test("a flip leaves the sides exactly where they were")
    func flippingDoesNotTouchTheSides() {
        let size = CGSize(width: 420, height: 560)

        for flipped in [true, false] {
            #expect(
                PanelResize.edge(at: CGPoint(x: 2, y: 280), in: size, isFlipped: flipped) == .left)
            #expect(
                PanelResize.edge(at: CGPoint(x: 418, y: 280), in: size, isFlipped: flipped)
                    == .right)
        }
    }

    // MARK: - The bands the pointer is drawn over

    /// The cursor rects and the hit test have to describe the same eight rectangles.
    @Test("every band contains the point the hit test reads as its edge")
    func bandsAgreeWithTheHitTest() {
        let size = CGSize(width: 420, height: 560)

        for flipped in [true, false] {
            for (rect, edge) in PanelResize.borders(in: size, isFlipped: flipped) {
                let middle = CGPoint(x: rect.midX, y: rect.midY)
                #expect(
                    PanelResize.edge(at: middle, in: size, isFlipped: flipped) == edge,
                    "the \(edge) band is drawn somewhere the hit test does not agree with")
            }
        }
    }

    @Test("the corners come last, so they win the overlap")
    func cornersLast() {
        let bands = PanelResize.borders(in: CGSize(width: 420, height: 560))
        let corners: Set<PanelEdge> = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let firstCorner = bands.firstIndex { corners.contains($0.edge) }

        #expect(bands.count == 8)
        #expect(firstCorner == 4, "an edge is drawn after a corner and would cover it")
    }

    @Test("and every band is inside the panel")
    func bandsStayInside() {
        let size = CGSize(width: 420, height: 560)

        for flipped in [true, false] {
            for (rect, edge) in PanelResize.borders(in: size, isFlipped: flipped) {
                #expect(rect.minX >= 0 && rect.minY >= 0, "\(edge) starts outside the panel")
                #expect(
                    rect.maxX <= size.width && rect.maxY <= size.height,
                    "\(edge) runs past the panel")
            }
        }
    }

    // MARK: - What a drag does

    @Test("the right border grows the panel and leaves the left one where it was")
    func draggingRight() {
        let after = resized(.right, by: CGSize(width: 120, height: 0))

        #expect(after.width == 540)
        #expect(after.minX == Self.frame.minX)
        #expect(after.height == Self.frame.height)
    }

    /// The edge opposite the one held does not move, so a resize feels like pulling the border.
    @Test("the left border grows it the other way, and the right edge stays put")
    func draggingLeft() {
        let after = resized(.left, by: CGSize(width: -120, height: 0))

        #expect(after.width == 540)
        #expect(after.maxX == Self.frame.maxX)
    }

    @Test("the top border grows upwards, which in AppKit's coordinates leaves the origin alone")
    func draggingTop() {
        let after = resized(.top, by: CGSize(width: 0, height: 80))

        #expect(after.height == 640)
        #expect(after.minY == Self.frame.minY)
    }

    @Test("and the bottom border grows downwards, which moves it")
    func draggingBottom() {
        let after = resized(.bottom, by: CGSize(width: 0, height: -80))

        #expect(after.height == 640)
        #expect(after.maxY == Self.frame.maxY)
        #expect(after.minY == Self.frame.minY - 80)
    }

    @Test("a corner moves both dimensions at once")
    func draggingACorner() {
        let after = resized(.bottomLeft, by: CGSize(width: -60, height: -40))

        #expect(after.width == 480)
        #expect(after.height == 600)
        #expect(after.maxX == Self.frame.maxX)
        #expect(after.maxY == Self.frame.maxY)
    }

    @Test("an edge that changes only one dimension leaves the other exactly alone")
    func oneDimensionAtATime() {
        #expect(resized(.left, by: CGSize(width: -50, height: 999)).height == Self.frame.height)
        #expect(resized(.top, by: CGSize(width: 999, height: 50)).width == Self.frame.width)
    }

    // MARK: - The floor

    @Test("the panel cannot be dragged smaller than it can be read at")
    func theMinimum() {
        let after = resized(.bottomRight, by: CGSize(width: -900, height: 900))

        #expect(after.width == PanelResize.minimum.width)
        #expect(after.height == PanelResize.minimum.height)
    }

    /// Measured from where the drag began, so the minimum clamps nothing away for the rest of the gesture.
    @Test("and a drag that hits the floor and comes back out follows the pointer again")
    func comingBackOffTheFloor() {
        let squashed = resized(.right, by: CGSize(width: -900, height: 0))
        #expect(squashed.width == PanelResize.minimum.width)

        let out = resized(.right, by: CGSize(width: 100, height: 0))
        #expect(out.width == 520, "the second step is measured from the original frame")
    }

    // MARK: - Staying on the screen

    /// A borderless panel gets no AppKit protection, and an edge past the menu bar cannot be dragged back.
    @Test("a border dragged off the top of the screen is held at the edge")
    func heldAtTheTop() {
        let after = resized(.top, by: CGSize(width: 0, height: 400), within: Self.visible)

        #expect(after.maxY == Self.visible.maxY)
        #expect(after.minY == Self.frame.minY)
    }

    @Test("and off the left, and off the bottom")
    func heldAtTheOtherEdges() {
        let leftward = resized(
            .left, by: CGSize(width: -2000, height: 0),
            from: CGRect(x: 40, y: 328, width: 420, height: 560), within: Self.visible)
        #expect(leftward.minX == Self.visible.minX)
        #expect(leftward.maxX == 460)

        let downward = resized(
            .bottom, by: CGSize(width: 0, height: -2000), within: Self.visible)
        #expect(downward.minY == Self.visible.minY)
        #expect(downward.maxY == Self.frame.maxY)
    }

    /// The opposite border is not pulled about while the user is holding this one.
    @Test("holding one border never moves the one opposite it")
    func theOppositeBorderIsLeftAlone() {
        for edge in PanelEdge.allCases {
            let after = resized(
                edge, by: CGSize(width: 300, height: 300), within: Self.visible)
            let moves = edge.movesOrigin
            if edge.changesWidth {
                #expect(
                    moves.x ? after.maxX == Self.frame.maxX : after.minX == Self.frame.minX,
                    "\(edge) moved the border opposite the one being dragged")
            }
            if edge.changesHeight {
                #expect(
                    moves.y ? after.maxY == Self.frame.maxY : after.minY == Self.frame.minY,
                    "\(edge) moved the border opposite the one being dragged")
            }
        }
    }

    /// A screen smaller than the minimum loses, the same choice `PanelPlacement.clamped` makes.
    @Test("a screen too small for the minimum does not shrink the panel below it")
    func aScreenSmallerThanTheMinimum() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 200)
        let after = resized(
            .right, by: CGSize(width: 500, height: 0),
            from: CGRect(x: 0, y: 0, width: 420, height: 560), within: tiny)

        #expect(after.width >= PanelResize.minimum.width)
    }

    /// With no screen to measure against there is nothing to hold it inside.
    @Test("and with no screen at all the drag still works")
    func noScreen() {
        #expect(resized(.right, by: CGSize(width: 100, height: 0), within: nil).width == 520)
    }
}
