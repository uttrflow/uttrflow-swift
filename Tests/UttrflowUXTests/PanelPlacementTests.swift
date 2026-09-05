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
