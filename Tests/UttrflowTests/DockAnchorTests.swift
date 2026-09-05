// Tests for dock placement.

import CoreGraphics
import UttrflowCore
import Testing

@testable import Uttrflow

/// The main display of a Mac with a menu bar and a Dock: a visible frame that starts above the origin.
private let mainScreen = CGRect(x: 0, y: 84, width: 1512, height: 862)

/// A second display to the left of the main one, whose negative coordinates catch origin-from-width bugs.
private let leftScreen = CGRect(x: -1920, y: -240, width: 1920, height: 1055)

private let pill = CGSize(width: 298, height: 64)
private let grip = CGSize(width: 21, height: 58)

@Suite("Dock placement")
struct DockAnchorTests {

    // MARK: - Anchor points

    @Test("Each anchor names a point inset from the edge it belongs to")
    func anchorPoints() {
        let margin = DockPlacement.margin
        #expect(
            DockPlacement.anchorPoint(for: .bottomLeft, in: mainScreen)
                == CGPoint(x: mainScreen.minX + margin, y: mainScreen.minY + margin))
        #expect(
            DockPlacement.anchorPoint(for: .bottomCentre, in: mainScreen)
                == CGPoint(x: mainScreen.midX, y: mainScreen.minY + margin))
        #expect(
            DockPlacement.anchorPoint(for: .bottomRight, in: mainScreen)
                == CGPoint(x: mainScreen.maxX - margin, y: mainScreen.minY + margin))
        #expect(
            DockPlacement.anchorPoint(for: .rightEdge, in: mainScreen)
                == CGPoint(x: mainScreen.maxX - margin, y: mainScreen.midY))
    }

    @Test("Anchor points honour a supplied margin")
    func anchorPointsWithCustomMargin() {
        #expect(
            DockPlacement.anchorPoint(for: .bottomLeft, in: mainScreen, margin: 40)
                == CGPoint(x: 40, y: 124))
    }

    // MARK: - Origins

    @Test("Bottom left sits a margin in from the bottom-left of the visible frame")
    func bottomLeftOrigin() {
        let origin = DockPlacement.origin(for: .bottomLeft, panelSize: pill, in: mainScreen)
        #expect(origin == CGPoint(x: 16, y: 100))
    }

    @Test("Bottom centre centres the panel, not its edge")
    func bottomCentreOrigin() {
        let origin = DockPlacement.origin(for: .bottomCentre, panelSize: pill, in: mainScreen)
        #expect(origin == CGPoint(x: mainScreen.midX - pill.width / 2, y: 100))
        #expect(origin.x + pill.width / 2 == mainScreen.midX)
    }

    @Test("Bottom right keeps its right-hand edge fixed as the panel widens")
    func bottomRightGrowsLeftwards() {
        let resting = DockPlacement.frame(for: .bottomRight, panelSize: grip, in: mainScreen)
        let listening = DockPlacement.frame(for: .bottomRight, panelSize: pill, in: mainScreen)
        #expect(resting.maxX == listening.maxX)
        #expect(listening.minX < resting.minX)
        #expect(resting.maxX == mainScreen.maxX - DockPlacement.margin)
    }

    @Test("Right edge is centred vertically and pinned to the right")
    func rightEdgeOrigin() {
        let origin = DockPlacement.origin(for: .rightEdge, panelSize: grip, in: mainScreen)
        #expect(origin.x == mainScreen.maxX - DockPlacement.margin - grip.width)
        #expect(origin.y + grip.height / 2 == mainScreen.midY)
    }

    @Test("A custom margin moves every anchor")
    func originHonoursCustomMargin() {
        let origin = DockPlacement.origin(
            for: .bottomRight, panelSize: pill, in: mainScreen, margin: 4)
        #expect(origin == CGPoint(x: mainScreen.maxX - 4 - pill.width, y: mainScreen.minY + 4))
    }

    // MARK: - Screens that do not start at zero

    @Test(
        "Every anchor lands inside a screen at a non-zero origin",
        arguments: DockAnchor.allCases)
    func staysInsideTheMainScreen(anchor: DockAnchor) {
        let frame = DockPlacement.frame(for: anchor, panelSize: pill, in: mainScreen)
        #expect(mainScreen.contains(frame))
    }

    @Test(
        "Every anchor lands inside a screen at a negative origin",
        arguments: DockAnchor.allCases)
    func staysInsideANegativeOriginScreen(anchor: DockAnchor) {
        let frame = DockPlacement.frame(for: anchor, panelSize: pill, in: leftScreen)
        #expect(leftScreen.contains(frame))
        // A panel placed as though the screen began at zero would be two thousand points away.
        #expect(frame.minX < 0)
    }

    @Test("A left-hand display's bottom-left anchor is negative, not zero")
    func negativeScreenBottomLeft() {
        let origin = DockPlacement.origin(for: .bottomLeft, panelSize: pill, in: leftScreen)
        #expect(origin == CGPoint(x: -1904, y: -224))
    }

    @Test("A left-hand display's centre anchor is negative too")
    func negativeScreenBottomCentre() {
        let origin = DockPlacement.origin(for: .bottomCentre, panelSize: pill, in: leftScreen)
        #expect(origin == CGPoint(x: leftScreen.midX - pill.width / 2, y: -224))
        #expect(origin.x < 0)
    }

    // MARK: - Clamping

    @Test("A panel wider than the screen is pinned rather than pushed off it")
    func panelWiderThanTheScreen() {
        let tiny = CGRect(x: 200, y: 100, width: 120, height: 90)
        let huge = CGSize(width: 400, height: 300)
        for anchor in DockAnchor.allCases {
            let origin = DockPlacement.origin(for: anchor, panelSize: huge, in: tiny)
            #expect(origin == CGPoint(x: tiny.minX, y: tiny.minY))
        }
    }

    @Test("A margin larger than the screen cannot push the panel out of view")
    func absurdMargin() {
        let frame = DockPlacement.frame(
            for: .bottomLeft, panelSize: grip, in: mainScreen, margin: 9_000)
        #expect(mainScreen.contains(frame))
    }

    @Test("A panel taller than the visible frame keeps its bottom edge on screen")
    func panelTallerThanTheScreen() {
        let short = CGRect(x: -50, y: -50, width: 800, height: 60)
        let tall = CGSize(width: 100, height: 400)
        let origin = DockPlacement.origin(for: .rightEdge, panelSize: tall, in: short)
        #expect(origin.y == short.minY)
    }
}
