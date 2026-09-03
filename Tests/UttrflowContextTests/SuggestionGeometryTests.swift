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

/// The strip, which is wider than it is tall because it is a line of text.
private let strip = CGSize(width: 260, height: 24)

@Suite("Suggestion geometry")
struct SuggestionGeometryTests {

    // MARK: - The inline ghost

    @Test("The ghost starts where the caret is, on the caret's own line")
    func ghostContinuesTheLine() {
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: caret, window: documentWindow, screen: mainScreen,
            size: strip)
        #expect(anchor.placement == .inlineGhost)
        #expect(anchor.frame.origin == CGPoint(x: caret.maxX, y: caret.minY))
    }

    @Test("A ghost that would run off the right of the screen is pulled back onto it")
    func ghostNearTheRightEdge() {
        let late = CGRect(x: mainScreen.maxX - 6, y: 500, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: late, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.placement == .inlineGhost)
        #expect(mainScreen.contains(anchor.frame))
        #expect(anchor.frame.maxX == mainScreen.maxX)
    }

    // MARK: - The caret chip

    @Test("The chip hangs a gap under the caret, centred on it")
    func chipUnderTheCaret() {
        let anchor = SuggestionGeometry.anchor(
            for: .caretChip, caret: caret, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.placement == .caretChip)
        #expect(anchor.frame.midX == caret.midX)
        #expect(anchor.frame.maxY == caret.minY - SuggestionGeometry.gap)
    }

    @Test("A chip with no room under the caret flips above it rather than off the screen")
    func chipFlipsAboveTheCaret() {
        let low = CGRect(x: 620, y: mainScreen.minY + 4, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .caretChip, caret: low, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.frame.minY == low.maxY + SuggestionGeometry.gap)
        #expect(mainScreen.contains(anchor.frame))
    }

    // MARK: - The window strip

    @Test("The strip stands on the window's bottom edge, centred on the window")
    func stripAlongTheWindow() {
        let anchor = SuggestionGeometry.anchor(
            for: .windowStrip, caret: caret, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.placement == .windowStrip)
        #expect(anchor.frame.midX == documentWindow.midX)
        #expect(anchor.frame.minY == documentWindow.minY + SuggestionGeometry.margin)
    }

    @Test("With no window to stand on, the strip stands on the bottom of the screen")
    func stripFallsBackToTheScreen() {
        let anchor = SuggestionGeometry.anchor(
            for: .windowStrip, caret: nil, window: nil, screen: mainScreen, size: strip)
        #expect(anchor.frame.midX == mainScreen.midX)
        #expect(anchor.frame.minY == mainScreen.minY + SuggestionGeometry.margin)
    }

    @Test("A window on a display that is no longer there is not stood on")
    func stripIgnoresAWindowOffTheScreen() {
        let elsewhere = CGRect(x: -4000, y: -3000, width: 900, height: 700)
        let anchor = SuggestionGeometry.anchor(
            for: .windowStrip, caret: nil, window: elsewhere, screen: mainScreen, size: strip)
        #expect(anchor.frame.midX == mainScreen.midX)
        #expect(mainScreen.contains(anchor.frame))
    }

    // MARK: - Falling down the ladder

    @Test(
        "A caret rung with no caret rectangle falls all the way to the strip",
        arguments: [SuggestionPlacement.inlineGhost, .caretChip])
    func noCaretFallsToTheStrip(placement: SuggestionPlacement) {
        let anchor = SuggestionGeometry.anchor(
            for: placement, caret: nil, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.placement == .windowStrip)
        #expect(anchor.frame.minY == documentWindow.minY + SuggestionGeometry.margin)
    }

    @Test("A caret on a display this screen does not cover is no caret at all")
    func caretOffTheScreenFallsToTheStrip() {
        let elsewhere = CGRect(x: -1700, y: -100, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: .inlineGhost, caret: elsewhere, window: documentWindow, screen: mainScreen,
            size: strip)
        #expect(anchor.placement == .windowStrip)
    }

    @Test("A null caret rectangle is treated as no caret")
    func nullCaretFallsToTheStrip() {
        let anchor = SuggestionGeometry.anchor(
            for: .caretChip, caret: .null, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.placement == .windowStrip)
    }

    @Test("With neither a caret nor a window, every rung lands on the bottom of the screen")
    func nothingKnownFallsToTheScreen() {
        for placement in SuggestionPlacement.allCases {
            let anchor = SuggestionGeometry.anchor(
                for: placement, caret: nil, window: nil, screen: mainScreen, size: strip)
            #expect(anchor.placement == .windowStrip)
            #expect(anchor.frame.minY == mainScreen.minY + SuggestionGeometry.margin)
            #expect(anchor.frame.midX == mainScreen.midX)
        }
    }

    @Test("A rung is never climbed, only fallen from")
    func neverClimbsTheLadder() {
        let anchor = SuggestionGeometry.anchor(
            for: .windowStrip, caret: caret, window: documentWindow, screen: mainScreen, size: strip)
        #expect(anchor.placement == .windowStrip)
    }

    // MARK: - Staying on the screen

    @Test("Every rung lands inside the screen", arguments: SuggestionPlacement.allCases)
    func staysOnTheMainScreen(placement: SuggestionPlacement) {
        let anchor = SuggestionGeometry.anchor(
            for: placement, caret: caret, window: documentWindow, screen: mainScreen, size: strip)
        #expect(mainScreen.contains(anchor.frame))
    }

    @Test(
        "Every rung lands inside a screen with negative coordinates",
        arguments: SuggestionPlacement.allCases)
    func staysOnANegativeOriginScreen(placement: SuggestionPlacement) {
        let farCaret = CGRect(x: -1400, y: 300, width: 2, height: 17)
        let farWindow = CGRect(x: -1800, y: 60, width: 1000, height: 800)
        let anchor = SuggestionGeometry.anchor(
            for: placement, caret: farCaret, window: farWindow, screen: leftScreen, size: strip)
        #expect(leftScreen.contains(anchor.frame))
        // The failure this guards is arithmetic done as though the screen began at zero.
        #expect(anchor.frame.minX < 0)
    }

    @Test(
        "A caret at the very top of the screen keeps its chip on the screen",
        arguments: SuggestionPlacement.allCases)
    func caretAtTheTop(placement: SuggestionPlacement) {
        let high = CGRect(x: 1500, y: mainScreen.maxY - 4, width: 2, height: 17)
        let anchor = SuggestionGeometry.anchor(
            for: placement, caret: high, window: nil, screen: mainScreen, size: strip)
        #expect(mainScreen.contains(anchor.frame))
    }

    @Test(
        "A surface larger than the screen is pinned rather than pushed off it",
        arguments: SuggestionPlacement.allCases)
    func surfaceLargerThanTheScreen(placement: SuggestionPlacement) {
        let tiny = CGRect(x: 200, y: 100, width: 120, height: 90)
        let huge = CGSize(width: 400, height: 300)
        let anchor = SuggestionGeometry.anchor(
            for: placement, caret: CGRect(x: 240, y: 140, width: 2, height: 17),
            window: tiny, screen: tiny, size: huge)
        #expect(anchor.frame.origin == CGPoint(x: tiny.minX, y: tiny.minY))
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
        let one = SuggestionAnchor(placement: .caretChip, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        let other = SuggestionAnchor(placement: .caretChip, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(one == other)
        #expect(one != SuggestionAnchor(placement: .windowStrip, frame: one.frame))
    }
}
