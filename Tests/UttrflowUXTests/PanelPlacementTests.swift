import Foundation
import Testing

@testable import UttrflowUX

/// Where the panel opens. Almost all of this is about the cases a display gives you for
/// free — a screen that shrank, one that went away, one smaller than the panel.
@Suite("Where the quick panel opens")
struct PanelPlacementTests {
    /// A 1440×900 display with the menu bar taken off the top.
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    static let size = CGSize(width: 420, height: 560)

    @Test("with nothing remembered, it opens in the top-right corner")
    func topRightByDefault() {
        let origin = PanelPlacement.defaultOrigin(size: Self.size, in: Self.screen)

        #expect(origin.x == 1440 - 420 - PanelPlacement.margin)
        #expect(origin.y == 875 - 560 - PanelPlacement.margin)
    }

    /// AppKit's `y` grows upwards, so the top of the screen is the larger number and an
    /// origin is a panel's *bottom* edge. Getting either backwards puts the panel along
    /// the bottom of the display, which reads as correct in a diff. So this asks about
    /// the edges of the panel rather than about its origin.
    @Test("the panel's top and right edges are the ones near the screen's")
    func theTopIsUp() {
        let origin = PanelPlacement.defaultOrigin(size: Self.size, in: Self.screen)
        let panel = CGRect(origin: origin, size: Self.size)

        #expect(panel.maxY == Self.screen.maxY - PanelPlacement.margin)
        #expect(panel.maxX == Self.screen.maxX - PanelPlacement.margin)
        #expect(panel.minY > Self.screen.minY, "not flush with the bottom")
        #expect(panel.minX > Self.screen.midX, "in the right-hand half")
    }

    /// A screen whose origin is not zero: a second display to the right of the first, or
    /// a first one with a Dock on the left. The corner is that screen's corner.
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

    /// The display it was left on has been unplugged. Restoring the saved position
    /// literally would put the panel where nothing can be seen or reached — and there is
    /// no way back from that, because moving it needs it to be visible first.
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

    /// A panel taller than the screen has no position that fits. The arithmetic for
    /// "inside" inverts here, and an unguarded `min`/`max` pair answers with the *lower*
    /// bound of an empty range — off the top of the screen rather than on it.
    @Test("a panel bigger than the screen still opens somewhere reachable")
    func biggerThanTheScreen() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 300)

        let origin = PanelPlacement.origin(remembered: nil, size: Self.size, in: small)

        #expect(origin == CGPoint(x: 0, y: 0))
        #expect(origin.x >= small.minX)
        #expect(origin.y >= small.minY)
    }

    /// Clamping has to be idempotent, because the panel is placed on every open and a
    /// position that drifted by a margin each time would walk across the screen.
    @Test("clamping a position that is already fine changes nothing")
    func idempotent() {
        let once = PanelPlacement.defaultOrigin(size: Self.size, in: Self.screen)
        let twice = PanelPlacement.clamped(once, size: Self.size, in: Self.screen)

        #expect(once == twice)
    }
}
