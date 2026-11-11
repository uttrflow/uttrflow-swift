import AppKit
import Testing
import UttrflowCore
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Suggestion panel after a refused accept")
struct SuggestionPanelRefusalTests {
    private static let message = "Allow access, then try again."

    @Test("a refused accept draws the hidden offer again with the message under it")
    func restoresHiddenOfferWithNotice() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let panel = SuggestionPanelController(screenNotificationCenter: NotificationCenter())
        panel.frontWindow = { _ in }
        defer { panel.hide() }
        panel.show(
            .certain("git commit"), typed: "git c", placement: .inlineGhost,
            caret: CGRect(x: screen.minX + 200, y: screen.midY - 5, width: 0, height: 17),
            window: screen, fieldPointSize: 13)
        panel.hide()

        panel.restoreHidden(saying: Self.message)

        #expect(panel.drawn.inline != nil)
        #expect(panel.drawn.notice == Self.message)
    }

    @Test("a take-down keeps the offer for one put-back, and a request still draws the same without it")
    func takeDownKeepsOneOffer() {
        var request = SuggestionRequest()
        request.suggestion = .certain("git commit")
        let shown = request

        request.takeDown()
        request.takeDown()

        #expect(request.suggestion == .silent)
        let putBack = request.putBack()
        let putBackAgain = request.putBack()

        #expect(putBack)
        #expect(request.suggestion == .certain("git commit"))
        #expect(request.draws(sameAs: shown))
        #expect(!putBackAgain)
    }

    @Test("with no offer taken down, a refusal draws nothing")
    func nothingHiddenDrawsNothing() {
        let panel = SuggestionPanelController(screenNotificationCenter: NotificationCenter())
        panel.frontWindow = { _ in }

        panel.restoreHidden(saying: Self.message)

        #expect(panel.drawn.style == .hidden)
        #expect(panel.statusMessage == nil)
    }
}
