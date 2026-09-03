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

    @Test("A ghost that would run off the right of the screen is pulled back onto it")
    func ghostNearTheRightEdge() {
        let late = CGRect(x: mainScreen.maxX - 6, y: 500, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: late, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor?.placement == .inlineGhost)
        #expect(anchor.map { mainScreen.contains($0.frame) } == true)
        #expect(anchor?.frame.maxX == mainScreen.maxX)
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
        let high = CGRect(x: 1500, y: mainScreen.maxY - 4, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: high, window: nil, screen: mainScreen, size: strip)
        #expect(anchor.map { mainScreen.contains($0.frame) } == true)
    }

    @Test("A surface larger than the screen is pinned rather than pushed off it")
    func surfaceLargerThanTheScreen() {
        let tiny = CGRect(x: 200, y: 100, width: 120, height: 90)
        let huge = CGSize(width: 400, height: 300)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: CGRect(x: 240, y: 140, width: 2, height: 17),
            window: tiny, screen: tiny, size: huge)
        #expect(anchor?.frame.origin == CGPoint(x: tiny.minX, y: tiny.minY))
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
