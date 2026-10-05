// Tests that the ghost is drawn once, replaced whole, and cut to the room it has.

import AppKit
import SwiftUI
import Testing
import UttrflowPredict
import UttrflowUX

@testable import Uttrflow

/// A suggestion far longer than any field it could sit in.
private let longLine = String(repeating: "meet at the north gate at noon ", count: 40)

/// Every suggestion panel on screen in this process.
@MainActor
private var visiblePanels: [NSWindow] {
    NSApplication.shared.windows.filter { $0 is SuggestionPanel && $0.isVisible }
}

@MainActor
@Suite("The suggestion surface", .serialized)
struct SuggestionSurfaceTests {
    @Test("The view carries no animation, so a replaced ghost is never cross-faded over the one it replaces")
    func theViewDoesNotAnimate() {
        let view = SuggestionView(presentation: SuggestionPresentation(.certain("meeting")))
        let body = String(reflecting: type(of: view.body))
        #expect(!body.contains("Animation"), "\(body)")
    }

    @Test("A long ghost measures no wider than the room it is given, and its full width without one")
    func aLongGhostIsCut() {
        let capped = NSHostingView(
            rootView: SuggestionView(
                presentation: SuggestionPresentation(.certain(longLine), maximumWidth: 180)))
        let free = NSHostingView(
            rootView: SuggestionView(presentation: SuggestionPresentation(.certain(longLine))))
        #expect(capped.fittingSize.width <= 180)
        #expect(capped.fittingSize.width > 100)
        #expect(free.fittingSize.width > 1_000)
    }

    @Test("Two quick suggestions leave one panel on screen, drawing only the latest text")
    func twoQuickSuggestionsLeaveOne() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret)
        panel.show(.certain("meet at the north gate at noon"), placement: .inlineGhost, caret: caret)
        #expect(panel.drawn.inline?.candidate == "meet at the north gate at noon")
        #expect(panel.drawn.rows.count == 1)
        #expect(visiblePanels.count == 1)
        panel.hide()
        #expect(visiblePanels.isEmpty)
        #expect(panel.drawn.style == .hidden)
    }

    @Test("A display change withdraws the visible suggestion immediately")
    func displayChangeWithdrawsTheVisibleSuggestion() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController()
        defer { panel.hide() }
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret)
        #expect(panel.isShowing)

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(!panel.isShowing)
        #expect(panel.drawn.style == .hidden)
    }

    @Test("A suggestion with no room reports hidden and stops idle polling")
    func noRoomReportsHidden() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let field = CGRect(x: screen.midX, y: screen.midY - 5, width: 100, height: 28)
        let caret = CGRect(x: field.maxX, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret, field: field)
        defer { panel.hide() }
        #expect(!panel.isShowing)
        #expect(!panel.window.isVisible)
    }

    @Test(
        "A suggestion too long for the room to the field's edge is not drawn at all, so Tab cannot insert unseen words"
    )
    func aLongSuggestionIsNotDrawn() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.maxX - 300, y: screen.midY, width: 0, height: 17)
        let field = CGRect(x: screen.maxX - 500, y: screen.midY - 5, width: 400, height: 28)
        let panel = SuggestionPanelController.shared
        defer { panel.hide() }
        let drawn = panel.show(.certain(longLine), placement: .inlineGhost, caret: caret, field: field)
        #expect(!drawn)
        #expect(!panel.isShowing)
        #expect(!panel.window.isVisible)
        #expect(panel.drawn.inline == nil)
    }

    @Test("A suggestion that fits the room is drawn whole, inside the field and the screen")
    func aFittingSuggestionIsDrawnWhole() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.maxX - 300, y: screen.midY, width: 0, height: 17)
        let field = CGRect(x: screen.maxX - 500, y: screen.midY - 5, width: 400, height: 28)
        let panel = SuggestionPanelController.shared
        defer { panel.hide() }
        let drawn = panel.show(
            .certain("meet at noon"), typed: "meet", placement: .inlineGhost, caret: caret, field: field)
        #expect(drawn)
        #expect(panel.window.isVisible)
        #expect(panel.window.frame.minX == caret.maxX)
        #expect(panel.window.frame.maxX <= field.maxX)
        #expect(screen.contains(panel.window.frame))
        #expect(panel.drawn.inline?.ghost == " at noon")
        #expect(panel.drawn.maximumWidth == field.maxX - caret.maxX)
    }

    @Test("An open list with a row wider than its room is withdrawn before that row can be selected")
    func anOpenListWithATruncatedRowIsNotOffered() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let field = CGRect(x: screen.minX + 100, y: screen.midY - 5, width: 100, height: 28)
        let caret = CGRect(x: field.minX + 60, y: screen.midY, width: 0, height: 17)
        let room = field.maxX - caret.maxX
        let suggestion = Suggestion.choice(
            leader: "ok", others: ["long alternative that cannot fit in this field"])
        let presentation = SuggestionPresentation(
            suggestion, selection: SuggestionSelection(index: 0, hasMoved: true), maximumWidth: room)
        let rows = presentation.list
        let measuredWidths = rows.map {
            NSHostingView(rootView: SuggestionListRow(presentation: presentation, row: $0)).fittingSize.width
        }
        #expect(measuredWidths.first ?? .infinity <= room)
        #expect(measuredWidths.last ?? 0 > room)

        let panel = SuggestionPanelController()
        defer { panel.hide() }
        let shown = panel.show(
            suggestion, placement: .inlineGhost, caret: caret, field: field,
            selection: SuggestionSelection(index: 0, hasMoved: true))

        #expect(!shown)
        #expect(!panel.isShowing)
        #expect(panel.drawn.style == .hidden)
        #expect(panel.drawn.list.isEmpty)
    }

    @Test("Drawing the same offer at the same caret again does no layout, no placement and no fronting")
    func anUnchangedRedrawDoesNothing() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        defer { panel.hide() }
        panel.show(.certain("meeting"), typed: "mee", placement: .inlineGhost, caret: caret)
        let renders = panel.renders
        let placements = panel.placements
        for _ in 0..<10 {
            #expect(panel.show(.certain("meeting"), typed: "mee", placement: .inlineGhost, caret: caret))
        }
        // A read that reports the same caret half a point off is the same place.
        panel.show(
            .certain("meeting"), typed: "mee", placement: .inlineGhost, caret: caret.offsetBy(dx: 0.5, dy: 0))
        #expect(panel.renders == renders)
        #expect(panel.placements == placements)
        panel.show(
            .certain("meeting"), typed: "mee", placement: .inlineGhost, caret: caret.offsetBy(dx: 6, dy: 0))
        #expect(panel.renders == renders + 1)
        #expect(panel.placements == placements + 1)
    }

    @Test(
        "Typing the ghost's next letters keeps it on screen, moves it once per key and leaves the rest where it was"
    )
    func typingThroughTheGhostNeverHidesIt() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        defer { panel.hide() }
        let line = "see you at the station"
        panel.show(.certain(line), typed: "see", placement: .inlineGhost, caret: caret, fieldPointSize: 13)
        let withdrawals = panel.withdrawals
        let end = panel.window.frame.maxX
        var typed = "see"
        for character in " you " {
            typed.append(character)
            let placements = panel.placements
            #expect(panel.advance(to: typed, showing: .certain(line)))
            #expect(panel.placements == placements + 1)
            #expect(panel.window.isVisible)
            #expect(panel.drawn.inline?.ghost == String(line.dropFirst(typed.count)))
            #expect(abs(panel.window.frame.maxX - end) <= 2)
        }
        #expect(panel.withdrawals == withdrawals)
    }

    @Test("Typing through an RTL ghost keeps the remaining text at the same frame")
    func typingThroughRTLTheGhostNeverHidesIt() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 400, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        defer { panel.hide() }
        let line = "see you at the station"
        panel.show(
            .certain(line), typed: "see", placement: .inlineGhost, direction: .rightToLeft,
            caret: caret, fieldPointSize: 13)
        let withdrawals = panel.withdrawals
        let end = panel.window.frame.maxX
        var typed = "see"
        for character in " you " {
            typed.append(character)
            let placements = panel.placements
            #expect(panel.advance(to: typed, showing: .certain(line)))
            #expect(panel.placements == placements + 1)
            #expect(panel.window.isVisible)
            #expect(panel.drawn.inline?.ghost == String(line.dropFirst(typed.count)))
            #expect(abs(panel.window.frame.maxX - end) <= 2)
        }
        #expect(panel.withdrawals == withdrawals)
    }

    @Test("VoiceOver is told once as a suggestion appears, not on a redraw, and not when it cannot be drawn")
    func aSuggestionIsAnnouncedOnce() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        let original = panel.announce
        var heard: [String] = []
        panel.announce = { heard.append($0) }
        defer {
            panel.hide()
            panel.announce = original
        }
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret)
        panel.show(.certain("meeting"), typed: "mee", placement: .inlineGhost, caret: caret)
        #expect(heard == ["AI suggestion: meeting. Tab to accept."])
        panel.show(.certain("meeting"), placement: .inlineGhost)
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret)
        #expect(heard.count == 2)
        panel.hide()
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret, acceptKey: .rightArrow)
        #expect(heard.last == "AI suggestion: meeting. Right Arrow to accept.")
        #expect(heard.count == 3)
    }

    @Test("The panel has no window animation, so hiding a ghost does not wait out a fade")
    func thePanelDoesNotFade() {
        #expect(SuggestionPanelController.shared.window.animationBehavior == .none)
    }

    @Test("Hiding a panel that is already hidden does not replace the view")
    func aRedundantHideDoesNothing() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret)
        panel.hide()
        #expect(!panel.window.isVisible)
        let before = panel.renders
        panel.hide()
        panel.hide()
        #expect(panel.renders == before)
        #expect(panel.drawn.style == .hidden)
    }
}
