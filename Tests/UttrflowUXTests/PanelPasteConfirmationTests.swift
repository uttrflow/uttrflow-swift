import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// A hidden clip pasted into a field not known to hide it waits for the user's answer in the panel.
@Suite("Confirming a hidden clip's paste")
struct PanelHiddenPasteQuestionTests {
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

/// A multi-line clip pasted into a terminal asks through the same question, worded by its reason.
@Suite("Confirming a terminal paste in the panel")
struct PanelTerminalPasteQuestionTests {
    private static let clip = PanelFixture.clip("ls\npwd")

    private static func asking(cleaned: Bool = false) -> PanelSnapshot {
        PanelFixture.panel([clip]).askingBeforePaste(
            of: clip.id, cleaned: cleaned, reason: .multilineIntoTerminal(lines: 2))
    }

    @Test("Return pastes the plain clip as agreed, not as a hidden one")
    func returnConfirms() {
        let effect = Self.asking().applying(.return).outcome.effect

        #expect(effect == .closeAndInsertConfirmed(Self.clip.text, used: Self.clip.id))
    }

    @Test("the question is worded by the line count")
    func wording() throws {
        let sheet = try #require(PanelPresenter.present(Self.asking()).sheet)

        #expect(sheet.kind == .confirmingPaste)
        #expect(sheet.title == "This clip has 2 lines. Paste anyway?")
    }

    @Test("a clip that is gone pastes nothing")
    func gone() {
        let snapshot = PanelFixture.panel([PanelFixture.clip("other")]).askingBeforePaste(
            of: Self.clip.id, cleaned: false, reason: .multilineIntoTerminal(lines: 2))

        #expect(snapshot.applying(.return).outcome.effect == .redraw)
    }
}

/// The preference that turns the question off is a switch on the settings screen.
@Suite("The hidden clip confirmation switch")
struct HiddenClipConfirmationSwitchTests {
    @Test("the switch changes the setting and the screen reads it back")
    func switchRoundTrips() throws {
        let off = try SettingsEditor.apply(
            .toggle(.confirmsHiddenClipPaste, isOn: false), to: .default, given: .everything)

        #expect(!off.confirmsHiddenClipPaste)
        #expect(!SettingsPresenter.value(of: .confirmsHiddenClipPaste, in: off))
        #expect(SettingsPresenter.value(of: .confirmsHiddenClipPaste, in: .default))
    }
}
