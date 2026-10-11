import Foundation
import Testing
import UttrflowCore
import UttrflowClipboard

@testable import UttrflowUX

/// A hidden clip pasted into a field not known to hide it waits for the user's answer in the panel.
@Suite("Confirming a hidden clip's paste")
struct PanelHiddenPasteConfirmationTests {
    private static let secret = PanelFixture.clip("sk-live-abcdef123456", kind: .secret)

    private static func asking(unclassified: Bool = false, cleaned: Bool = false) -> PanelSnapshot {
        PanelFixture.panel([secret]).askingBeforePaste(
            of: secret.id, cleaned: cleaned,
            reason: unclassified ? .hiddenIntoUnreadableField : .hiddenIntoVisibleField)
    }

    @Test("choosing a hidden clip asks the app to classify the field before anything is pasted")
    func choosingStillAsksTheApp() {
        let effect = PanelFixture.panel([Self.secret]).applying(.return).outcome.effect

        #expect(effect == .closeAndInsertConcealed(Self.secret.text, used: Self.secret.id))
    }

    @Test("Return on the question pastes the hidden clip, marked as agreed")
    func returnConfirms() {
        let response = Self.asking().applying(.return)

        #expect(response.state.sheet == nil)
        #expect(
            response.outcome.effect
                == .closeAndInsertConfirmedConcealed(Self.secret.text, used: Self.secret.id))
    }

    @Test("Escape cancels: nothing is inserted and the panel stays up")
    func escapeCancels() {
        let response = Self.asking().applying(.escape)

        #expect(response.state.sheet == nil)
        #expect(response.outcome == .open)
        #expect(response.outcome.effect == .redraw)
    }

    @Test("the cleaned form stays the cleaned form after agreeing")
    func cleanedSurvives() {
        let dirty = PanelFixture.clip("sk-live\u{200B}abcdef123456", kind: .secret)
        let snapshot = PanelFixture.panel([dirty]).askingBeforePaste(
            of: dirty.id, cleaned: true, reason: .hiddenIntoVisibleField)

        let effect = snapshot.applying(.return).outcome.effect

        #expect(effect == .closeAndInsertConfirmedConcealed("sk-liveabcdef123456", used: dirty.id))
    }

    @Test("the question never carries the clip's words")
    func questionHidesTheClip() throws {
        for unclassified in [false, true] {
            let sheet = try #require(PanelPresenter.present(Self.asking(unclassified: unclassified)).sheet)
            let drawn = [
                sheet.title, sheet.note ?? "", sheet.confirmTitle, sheet.draft, sheet.conflict ?? "",
            ]

            #expect(sheet.kind == .confirmingPaste)
            #expect(sheet.isConfirmEnabled)
            #expect(drawn.allSatisfy { !$0.contains("sk-live") })
        }
    }

    @Test("a field that cannot be classified is worded differently")
    func unclassifiedWording() throws {
        let known = try #require(PanelPresenter.present(Self.asking()).sheet)
        let unknown = try #require(PanelPresenter.present(Self.asking(unclassified: true)).sheet)

        #expect(known.title != unknown.title)
    }

    @Test("a question is not revived when the panel reopens")
    func notResumed() {
        let resume = PanelResume(
            category: nil, selection: Self.secret.id,
            sheet: Self.asking().sheet, closedAt: PanelFixture.now)
        var reopened = PanelFixture.panel([Self.secret])

        reopened.restore(resume)

        #expect(reopened.sheet == nil)
    }

    @Test("the list behind the question stays inert")
    func listIsInert() {
        let response = Self.asking().applying(.down)

        #expect(response.state.sheet != nil)
        #expect(response.outcome == .open)
    }

    @Test("agreeing to a clip that is no longer hidden pastes nothing")
    func staleQuestion() {
        let plain = PanelFixture.clip("hello")
        let snapshot = PanelFixture.panel([plain]).askingBeforePaste(
            of: plain.id, cleaned: false, reason: .hiddenIntoVisibleField)

        #expect(snapshot.applying(.return).outcome.effect == .redraw)
    }
}
