import CoreGraphics
import Testing

@testable import UttrflowContext

/// The main display of a Mac with a menu bar and a Dock.
private let mainScreen = CGRect(x: 0, y: 84, width: 1512, height: 862)

/// A second display to the left of the main one, whose coordinates are negative.
private let leftScreen = CGRect(x: -1920, y: -240, width: 1920, height: 1055)

/// A caret in the middle of a document window: one line tall, a hair wide.
private let caret = CGRect(x: 620, y: 500, width: 2, height: 17)

/// The window that caret belongs to.
private let documentWindow = CGRect(x: 380, y: 200, width: 900, height: 700)

/// The surface, wider than it is tall because it is a line of text, taller than one line for a list.
private let strip = CGSize(width: 260, height: 24)

@Suite("Suggestion geometry")
struct SuggestionGeometryTests {

    // MARK: - The inline ghost

    @Test("The ghost hangs from the caret's top, so its first line sits on the caret's own line")
    func ghostContinuesTheLine() {
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: caret, window: documentWindow, screen: mainScreen,
            size: strip)
        #expect(anchor?.placement == .inlineGhost)
        // The surface's top edge is the caret's top edge, and it begins where the caret is.
        #expect(anchor?.frame.origin == CGPoint(x: caret.maxX, y: caret.maxY - strip.height))
        #expect(anchor?.frame.maxY == caret.maxY)
    }

    @Test(
        "A ghost that would run off the right of the screen is cut at the edge, never pulled back over the typed text"
    )
    func ghostNearTheRightEdge() {
        let late = CGRect(x: mainScreen.maxX - 100, y: 500, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: late, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor?.placement == .inlineGhost)
        #expect(anchor.map { mainScreen.contains($0.frame) } == true)
        #expect(anchor?.frame.minX == late.maxX)
        #expect(anchor?.frame.maxX == mainScreen.maxX)
    }

    @Test("A caret with less room than the minimum before the screen's edge draws nothing")
    func noRoomDrawsNothing() {
        let last = CGRect(x: mainScreen.maxX - 10, y: 500, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: last, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor == nil)
    }

    @Test("A dot narrower than the minimum still fits where only it does")
    func aSmallSurfaceNeedsOnlyItsOwnWidth() {
        let last = CGRect(x: mainScreen.maxX - 12, y: 500, width: 2, height: 17)
        let dot = CGSize(width: 7, height: 7)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: last, window: documentWindow, screen: mainScreen, size: dot)
        #expect(anchor?.frame.size == dot)
    }

    @Test("A long ghost stops at the field's right edge when the field's frame is known")
    func ghostStopsAtTheField() {
        let field = CGRect(x: 400, y: 490, width: 300, height: 30)
        let long = CGSize(width: 2_000, height: 24)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: caret, window: documentWindow, field: field, screen: mainScreen,
            size: long)
        #expect(anchor?.frame.minX == caret.maxX)
        #expect(anchor?.frame.maxX == field.maxX)
    }

    @Test("A field frame that does not hold the caret, or is caret-thin, is not trusted as the edge")
    func anUntrustworthyFieldIsIgnored() {
        let long = CGSize(width: 2_000, height: 24)
        for field in [
            CGRect(x: 10, y: 490, width: 300, height: 30), CGRect(x: 621, y: 490, width: 2, height: 17),
            CGRect.null,
        ] {
            let anchor = SuggestionGeometry.anchor(
                for: .inlineGhost, caret: caret, window: documentWindow, field: field, screen: mainScreen,
                size: long)
            #expect(anchor?.frame.maxX == mainScreen.maxX)
        }
    }

    @Test("The room after the caret is nothing once the caret is past the screen's right edge")
    func noRoomPastTheEdge() {
        let past = CGRect(x: mainScreen.maxX + 5, y: 500, width: 0, height: 17)
        #expect(SuggestionGeometry.availableWidth(caret: past, field: nil, screen: mainScreen) == nil)
        #expect(
            SuggestionGeometry.availableWidth(caret: caret, field: nil, screen: mainScreen)
                == mainScreen.maxX - caret.maxX)
    }

    @Test("A surface with no size, or a size that is not a number, is never placed")
    func aDegenerateSizeDrawsNothing() {
        for size in [
            CGSize.zero, CGSize(width: CGFloat.nan, height: 20), CGSize(width: 20, height: CGFloat.infinity),
        ] {
            let anchor = SuggestionGeometry.anchor(
                for: .inlineGhost, caret: caret, window: documentWindow, screen: mainScreen, size: size)
            #expect(anchor == nil)
        }
    }

    @Test("A thin insertion caret with no width is still a caret, not nothing")
    func zeroWidthCaretIsUsable() {
        let thin = CGRect(x: 620, y: 500, width: 0, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: thin, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor?.placement == .inlineGhost)
    }

    // MARK: - The list below the caret

    @Test("A taller surface hangs from the caret's top, so the list falls below the leader's line")
    func listHangsBelowTheCaret() {
        let list = CGSize(width: 260, height: 72)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: caret, window: documentWindow, screen: mainScreen, size: list)
        #expect(anchor?.placement == .inlineGhost)
        // The surface's top sits on the caret's top, so the leader is on the line and the rest below.
        #expect(anchor?.frame.maxY == caret.maxY)
        // The whole surface begins where the caret is, so the list is left-aligned under the leader.
        #expect(anchor?.frame.minX == caret.maxX)
    }

    @Test("A single candidate hangs from the caret's top the same way a list does")
    func loneGhostStaysInline() {
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: caret, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor?.frame.origin == CGPoint(x: caret.maxX, y: caret.maxY - strip.height))
    }

    // MARK: - Nothing is drawn off the caret's line

    @Test("The window strip is gone: it is never a placement the geometry will produce")
    func theStripIsGone() {
        let anchor = SuggestionGeometry.anchor(
            for: .windowStrip, caret: caret, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor == nil)
    }

    @Test("An inline ghost with no caret rectangle draws nothing, rather than falling to a box")
    func noCaretDrawsNothing() {
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: nil, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor == nil)
    }

    @Test("A caret on a display this screen does not cover is no caret at all")
    func caretOffTheScreenDrawsNothing() {
        let elsewhere = CGRect(x: -1700, y: -100, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: elsewhere, window: documentWindow, screen: mainScreen,
            size: strip)
        #expect(anchor == nil)
    }

    @Test("A null caret rectangle is treated as no caret")
    func nullCaretDrawsNothing() {
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: .null, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor == nil)
    }

    @Test("With no caret, no placement draws anything, whatever the window")
    func nothingKnownDrawsNothing() {
        for placement in SuggestionPlacement.allCases {
            let anchor = SuggestionGeometry.anchor(
                for: placement, caret: nil, window: documentWindow, screen: mainScreen, size: strip)
            #expect(anchor == nil)
        }
    }

    // MARK: - Staying on the screen

    @Test("The ghost always lands inside the screen")
    func staysOnTheMainScreen() {
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: caret, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.map { mainScreen.contains($0.frame) } == true)
    }

    @Test("The ghost lands inside a screen with negative coordinates")
    func staysOnANegativeOriginScreen() {
        let farCaret = CGRect(x: -1400, y: 300, width: 2, height: 17)
        let farWindow = CGRect(x: -1800, y: 60, width: 1000, height: 800)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: farCaret, window: farWindow, screen: leftScreen, size: strip)
        #expect(anchor.map { leftScreen.contains($0.frame) } == true)
        // The failure this guards is arithmetic done as though the screen began at zero.
        #expect((anchor?.frame.minX ?? 0) < 0)
    }

    @Test("A caret at the very top of the screen keeps the ghost on the screen")
    func caretAtTheTop() {
        let high = CGRect(x: 1000, y: mainScreen.maxY - 4, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: high, window: nil, screen: mainScreen, size: strip)
        #expect(anchor.map { mainScreen.contains($0.frame) } == true)
    }

    @Test("A surface larger than the screen is cut to it rather than hanging off it")
    func surfaceLargerThanTheScreen() {
        let tiny = CGRect(x: 200, y: 100, width: 120, height: 90)
        let huge = CGSize(width: 400, height: 300)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: CGRect(x: 240, y: 140, width: 2, height: 17),
            window: tiny, screen: tiny, size: huge)
        #expect(anchor?.frame == CGRect(x: 242, y: tiny.minY, width: tiny.maxX - 242, height: tiny.height))
    }

    @Test(
        "Whatever the caret, field, screen and size, a placed frame lies inside the screen and the field's edge"
    )
    func neverLeavesTheScreen() {
        var random = Seeded(seed: 516)
        let screens = [mainScreen, leftScreen, CGRect(x: 1512, y: -1200, width: 2560, height: 1415)]
        var placed = 0
        for _ in 0..<5_000 {
            let screen = random.pick(screens)
            let caret = CGRect(
                x: CGFloat.random(in: screen.minX - 400...screen.maxX + 400, using: &random),
                y: CGFloat.random(in: screen.minY - 400...screen.maxY + 400, using: &random),
                width: random.chance(0.7) ? 0 : CGFloat.random(in: 0...300, using: &random),
                height: CGFloat.random(in: 0...60, using: &random))
            let field: CGRect? =
                random.chance(0.3)
                ? nil
                : CGRect(
                    x: caret.minX - CGFloat.random(in: -200...800, using: &random), y: caret.minY - 5,
                    width: CGFloat.random(in: 0...2_000, using: &random), height: 30)
            let size = CGSize(
                width: CGFloat.random(in: 1...6_000, using: &random),
                height: CGFloat.random(in: 1...2_000, using: &random))
            guard
                let frame = SuggestionGeometry.anchor(
                    for: .inlineGhost, caret: caret, window: nil, field: field, screen: screen, size: size)?
                    .frame
            else { continue }
            placed += 1
            // A hair of slack for the one addition floating point cannot make exact.
            let tolerance: CGFloat = 0.001
            #expect(screen.insetBy(dx: -tolerance, dy: -tolerance).contains(frame))
            #expect(frame.width <= size.width && frame.height <= size.height)
            #expect(frame.minX == caret.maxX)
            if let field, field.width > SuggestionGeometry.minimumWidth, field.minX <= caret.maxX,
                caret.maxX <= field.maxX
            {
                #expect(frame.maxX <= field.maxX + tolerance)
            }
        }
        // Most carets land on the screen, so the property is exercised rather than vacuously true.
        #expect(placed > 1_000)
    }

    // MARK: - The other coordinate convention

    @Test("An Accessibility rectangle is flipped into AppKit's space")
    func flipsAnAccessibilityRectangle() {
        let fromAccessibility = CGRect(x: 620, y: 300, width: 2, height: 17)
        let flipped = SuggestionGeometry.fromAccessibility(
            fromAccessibility, primaryScreenMaxY: 982)
        #expect(flipped == CGRect(x: 620, y: 982 - 317, width: 2, height: 17))
    }

    @Test("Flipping twice returns the rectangle it started as")
    func flippingIsItsOwnInverse() {
        let flipped = SuggestionGeometry.fromAccessibility(caret, primaryScreenMaxY: 982)
        #expect(SuggestionGeometry.fromAccessibility(flipped, primaryScreenMaxY: 982) == caret)
    }

    // MARK: - The anchor itself

    @Test("Two anchors of the same rung and rectangle are the same anchor")
    func anchorsCompareByValue() {
        let one = SuggestionAnchor(
            placement: .inlineGhost, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        let other = SuggestionAnchor(
            placement: .inlineGhost, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(one == other)
        #expect(
            one != SuggestionAnchor(placement: .inlineGhost, frame: CGRect(x: 9, y: 9, width: 9, height: 9)))
    }
}
