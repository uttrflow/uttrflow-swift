// Tests for where the panel opens: the default corner, a remembered spot, and screens that changed.
import Foundation
import Testing

@testable import UttrflowUX

/// Where the panel opens, mostly the cases a display gives for free: shrunk, unplugged, too small.
@Suite("Where the quick panel opens")
struct PanelPlacementTests {
    /// A 1440×900 display with the menu bar taken off the top.
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    /// The design's panel size.
    static let size = CGSize(width: 420, height: 560)

    @Test("with nothing remembered, it opens in the top-right corner")
    func topRightByDefault() {
        let origin = PanelPlacement.defaultOrigin(size: Self.size, in: Self.screen)

        #expect(origin.x == 1440 - 420 - PanelPlacement.margin)
        #expect(origin.y == 875 - 560 - PanelPlacement.margin)
    }

    /// AppKit's `y` grows upwards and an origin is a panel's bottom edge, so this asks about the edges.
    @Test("the panel's top and right edges are the ones near the screen's")
    func theTopIsUp() {
        let origin = PanelPlacement.defaultOrigin(size: Self.size, in: Self.screen)
        let panel = CGRect(origin: origin, size: Self.size)

        #expect(panel.maxY == Self.screen.maxY - PanelPlacement.margin)
        #expect(panel.maxX == Self.screen.maxX - PanelPlacement.margin)
        #expect(panel.minY > Self.screen.minY, "not flush with the bottom")
        #expect(panel.minX > Self.screen.midX, "in the right-hand half")
    }

    /// A screen whose origin is not zero: a second display, or a Dock on the left.
    @Test("the corner belongs to the screen it is opening on")
    func honoursTheScreensOwnOrigin() {
        let second = CGRect(x: 1440, y: 200, width: 1000, height: 600)

        let origin = PanelPlacement.defaultOrigin(size: Self.size, in: second)

        #expect(origin.x == 2440 - 420 - PanelPlacement.margin)
        #expect(origin.y == 800 - 560 - PanelPlacement.margin)
    }

    @Test("a remembered position is used as it is")
    func rememberedWins() {
        let placed = CGPoint(x: 300, y: 200)

        let origin = PanelPlacement.origin(remembered: placed, size: Self.size, in: Self.screen)

        #expect(origin == placed)
    }

    @Test("and with nothing remembered it falls back to the corner")
    func nothingRemembered() {
        let origin = PanelPlacement.origin(remembered: nil, size: Self.size, in: Self.screen)

        #expect(origin == PanelPlacement.defaultOrigin(size: Self.size, in: Self.screen))
    }

    /// A saved position on an unplugged display would put the panel where it cannot be seen or moved.
    @Test("a position on a display that has gone is pulled back on screen")
    func pulledBack() {
        let onASecondDisplay = CGPoint(x: 2200, y: 1400)

        let origin = PanelPlacement.origin(
            remembered: onASecondDisplay, size: Self.size, in: Self.screen)

        #expect(origin.x + Self.size.width <= Self.screen.maxX)
        #expect(origin.y + Self.size.height <= Self.screen.maxY)
        #expect(origin.x >= Self.screen.minX)
        #expect(origin.y >= Self.screen.minY)
    }

    @Test("and one off the bottom-left is pulled back too")
    func pulledBackTheOtherWay() {
        let origin = PanelPlacement.origin(
            remembered: CGPoint(x: -500, y: -500), size: Self.size, in: Self.screen)

        #expect(origin == CGPoint(x: 0, y: 0))
    }

    /// A panel taller than the screen has no position that fits, and a naive `min`/`max` goes off the top.
    @Test("a panel bigger than the screen still opens somewhere reachable")
    func biggerThanTheScreen() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 300)

        let origin = PanelPlacement.origin(remembered: nil, size: Self.size, in: small)

        #expect(origin == CGPoint(x: 0, y: 0))
        #expect(origin.x >= small.minX)
        #expect(origin.y >= small.minY)
    }

    /// Clamping is idempotent, or a position drifting by a margin each open would walk across the screen.
    @Test("clamping a position that is already fine changes nothing")
    func idempotent() {
        let once = PanelPlacement.defaultOrigin(size: Self.size, in: Self.screen)
        let twice = PanelPlacement.clamped(once, size: Self.size, in: Self.screen)

        #expect(once == twice)
    }
}

/// Each display keeps its own spot, so a panel left on one never opens jammed against another's edge.
@Suite("Where the quick panel opens with two displays")
struct PanelSpotsTests {
    /// A laptop display at the origin, with the menu bar taken off the top.
    static let displayA = CGRect(x: 0, y: 0, width: 1440, height: 875)
    /// A larger display to its right.
    static let displayB = CGRect(x: 1440, y: 0, width: 2560, height: 1415)
    static let a: UInt32 = 1
    static let b: UInt32 = 2
    static let size = PanelPlacementTests.size

    @Test("a spot near A's top-left does not pin the panel to B's left edge")
    func spotOnAOpeningOnB() {
        var spots = PanelSpots()
        spots.remember(CGPoint(x: 12, y: 303), on: Self.a)

        let origin = spots.origin(on: Self.b, size: Self.size, in: Self.displayB)

        #expect(origin == PanelPlacement.defaultOrigin(size: Self.size, in: Self.displayB))
        #expect(origin != CGPoint(x: 1440, y: 303), "not flush against B's left edge")
    }

    @Test("a spot near B's top-right does not pin the panel to A's right edge")
    func spotOnBOpeningOnA() {
        var spots = PanelSpots()
        spots.remember(CGPoint(x: 3568, y: 843), on: Self.b)

        let origin = spots.origin(on: Self.a, size: Self.size, in: Self.displayA)

        #expect(origin == PanelPlacement.defaultOrigin(size: Self.size, in: Self.displayA))
        #expect(origin != CGPoint(x: 1020, y: 315), "not flush against A's right edge")
    }

    @Test("each display opens where it was left, whichever was dragged last")
    func eachDisplayKeepsItsOwn() {
        var spots = PanelSpots()
        spots.remember(CGPoint(x: 12, y: 303), on: Self.a)
        spots.remember(CGPoint(x: 3000, y: 700), on: Self.b)

        #expect(spots.origin(on: Self.a, size: Self.size, in: Self.displayA) == CGPoint(x: 12, y: 303))
        #expect(spots.origin(on: Self.b, size: Self.size, in: Self.displayB) == CGPoint(x: 3000, y: 700))
    }

    /// A display that shrank, or came back arranged differently, still never loses the panel off screen.
    @Test("a display's own spot is still clamped into it")
    func ownSpotIsClamped() {
        var spots = PanelSpots()
        spots.remember(CGPoint(x: 3900, y: 1300), on: Self.b)
        let shrunk = CGRect(x: 1440, y: 0, width: 1920, height: 1055)

        let origin = spots.origin(on: Self.b, size: Self.size, in: shrunk)

        #expect(origin == PanelPlacement.clamped(CGPoint(x: 3900, y: 1300), size: Self.size, in: shrunk))
        #expect(CGRect(origin: origin, size: Self.size).maxX <= shrunk.maxX)
    }

    @Test("a screen with no number opens in the default corner")
    func unknownDisplay() {
        var spots = PanelSpots()
        spots.remember(CGPoint(x: 12, y: 303), on: Self.a)

        let origin = spots.origin(on: nil, size: Self.size, in: Self.displayA)

        #expect(origin == PanelPlacement.defaultOrigin(size: Self.size, in: Self.displayA))
    }

    @Test("the stored form reads back as it was written, and skips what is malformed")
    func propertyListRoundTrip() {
        var spots = PanelSpots()
        spots.remember(CGPoint(x: 12, y: 303), on: Self.a)
        spots.remember(CGPoint(x: 3000.5, y: 700), on: Self.b)

        #expect(PanelSpots(propertyList: spots.propertyList) == spots)
        let damaged: [String: Any] = ["1": [12.0, 303.0], "two": [1.0, 2.0], "3": [1.0], "4": "x"]
        #expect(PanelSpots(propertyList: damaged) == PanelSpots(origins: [1: CGPoint(x: 12, y: 303)]))
        #expect(PanelSpots(propertyList: nil) == PanelSpots())
    }
}
