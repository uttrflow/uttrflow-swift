import AppKit
import Testing
import UttrflowCore
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Suggestion panel after a refused accept")
struct SuggestionPanelRefusalTests {
    private static let message = "Allow access, then try again."

    /// Shows `git commit` at a caret on the first screen.
    private static func showOffer(on panel: SuggestionPanelController) throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        panel.show(
            .certain("git commit"), typed: "git c", placement: .inlineGhost,
            caret: CGRect(x: screen.minX + 200, y: screen.midY - 5, width: 0, height: 17),
            window: screen, fieldPointSize: 13)
    }

    /// Does what a refused accept does: puts back the offer the hide took down, if one is still held.
    private static func refuse(on panel: SuggestionPanelController) {
        if let offer = panel.takenDownOffer() { panel.putBack(offer, saying: message) }
    }

    @Test("the same offer drawn again after the message is cleared drops the message")
    func clearedMessageIsRedrawn() throws {
        let panel = SuggestionPanelController(screenNotificationCenter: NotificationCenter())
        panel.frontWindow = { _ in }
        defer { panel.hide() }
        try Self.showOffer(on: panel)
        panel.hide()
        Self.refuse(on: panel)

        panel.statusMessage = nil
        try Self.showOffer(on: panel)

        #expect(panel.drawn.inline != nil)
        #expect(panel.drawn.notice == nil)
    }

    @Test("an offer hidden again before the refusal arrives is not put back")
    func offerWithdrawnMeanwhileStaysDown() throws {
        let panel = SuggestionPanelController(screenNotificationCenter: NotificationCenter())
        panel.frontWindow = { _ in }
        defer { panel.hide() }
        try Self.showOffer(on: panel)
        panel.hide()
        panel.hide()

        Self.refuse(on: panel)

        #expect(panel.drawn.style == .hidden)
    }

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

        Self.refuse(on: panel)

        #expect(panel.drawn.inline != nil)
        #expect(panel.drawn.notice == Self.message)
    }

    @Test("a take-down holds the offer until the next one, and the held offer never changes what is drawn")
    func takeDownHoldsTheOffer() {
        var request = SuggestionRequest()
        request.suggestion = .certain("git commit")
        var silent = request
        silent.suggestion = .silent

        let tookOffer = request.takeDown()

        #expect(tookOffer)
        #expect(request.takenDown == .certain("git commit"))
        #expect(request.draws(sameAs: silent))

        let tookAgain = request.takeDown()

        #expect(!tookAgain)
        #expect(request.takenDown == nil)
    }

    @Test("with no offer taken down, a refusal draws nothing")
    func nothingHiddenDrawsNothing() {
        let panel = SuggestionPanelController(screenNotificationCenter: NotificationCenter())
        panel.frontWindow = { _ in }

        Self.refuse(on: panel)

        #expect(panel.takenDownOffer() == nil)
        #expect(panel.drawn.style == .hidden)
        #expect(panel.statusMessage == nil)
    }
}
