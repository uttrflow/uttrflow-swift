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
}
