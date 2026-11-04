import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// A multi-line clip pasted into a terminal is the one paste that asks, worded by its reason.
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

    @Test("a hidden clip into a terminal stays concealed when agreed")
    func hiddenInTerminal() {
        let secret = PanelFixture.clip("-----BEGIN PRIVATE KEY-----\nabc", kind: .secret)
        let asked = PanelFixture.panel([secret]).askingBeforePaste(
            of: secret.id, cleaned: false, reason: .multilineIntoTerminal(lines: 2))

        #expect(
            asked.applying(.return).outcome.effect
                == .closeAndInsertConfirmedConcealed(secret.text, used: secret.id))
    }

    @Test("a clip that is gone pastes nothing")
    func gone() {
        let snapshot = PanelFixture.panel([PanelFixture.clip("other")]).askingBeforePaste(
            of: Self.clip.id, cleaned: false, reason: .multilineIntoTerminal(lines: 2))

        #expect(snapshot.applying(.return).outcome.effect == .redraw)
    }
}

/// A chosen hidden clip never asks; it goes straight down the concealed route.
@Suite("Choosing a hidden clip in the panel")
struct PanelHiddenClipChoiceTests {
    private static let secret = PanelFixture.clip("Vb4nM7xQ2p-invented", kind: .secret)

    @Test("Return pastes it at once, concealed")
    func returnPastes() {
        var panel = PanelFixture.panel([Self.secret])
        panel.selection = Self.secret.id
        let response = panel.applying(.return)

        #expect(response.state.sheet == nil)
        #expect(response.outcome.effect == .closeAndInsertConcealed(Self.secret.text, used: Self.secret.id))
    }

    @Test("a click pastes it at once, concealed")
    func clickPastes() {
        let response = PanelFixture.panel([Self.secret]).applying(.choose(Self.secret.id))

        #expect(response.state.sheet == nil)
        #expect(response.outcome.effect == .closeAndInsertConcealed(Self.secret.text, used: Self.secret.id))
    }

    @Test("copying it goes to the clipboard, concealed")
    func copies() {
        #expect(
            PanelOutcome.copy(Self.secret).effect == .closeAndCopyConcealed(Self.secret.text, used: Self.secret.id))
    }
}
