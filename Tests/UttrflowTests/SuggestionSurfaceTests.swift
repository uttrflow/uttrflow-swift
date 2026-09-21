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

    @Test("A long suggestion at a caret near the edge stays inside the field and the screen")
    func aLongSuggestionStaysOnScreen() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.maxX - 300, y: screen.midY, width: 0, height: 17)
        let field = CGRect(x: screen.maxX - 500, y: screen.midY - 5, width: 400, height: 28)
        let panel = SuggestionPanelController.shared
        panel.show(.certain(longLine), placement: .inlineGhost, caret: caret, field: field)
        defer { panel.hide() }
        #expect(panel.window.isVisible)
        #expect(panel.window.frame.minX == caret.maxX)
        #expect(panel.window.frame.maxX <= field.maxX)
        #expect(screen.contains(panel.window.frame))
        #expect(panel.drawn.maximumWidth == field.maxX - caret.maxX)
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
