import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// B6 — for a note or a formatted snippet the user knows which of the two forms they
/// want and the app cannot, so it is a modifier rather than a mode.
@Suite("B6 · pasting without the formatting")
struct PanelPlainPasteTests {
    static let note = Clip(
        text: "Release checklist", kind: .text, copiedAt: PanelFixture.now,
        richText: "<h1>Release checklist</h1>")
    static let plain = PanelFixture.clip("just words", minutesAgo: 1)

    static func panel(_ clips: [Clip]) -> PanelSnapshot { PanelFixture.panel(clips) }

    /// Both flavours go up together and the receiving application takes the one it can
    /// read — which is the entire reason a clip keeps two.
    @Test("Return on a formatted clip carries the formatting")
    func returnCarriesIt() {
        let effect = Self.panel([Self.note]).applying(.return).outcome.effect

        #expect(
            effect
                == .closeAndInsertFormatted(
                    "Release checklist", richText: "<h1>Release checklist</h1>",
                    used: Self.note.id))
    }

    @Test("⌘⏎ carries the words and nothing else")
    func commandReturnStripsIt() {
        let effect = Self.panel([Self.note]).applying(.returnPlain).outcome.effect

        #expect(effect == .closeAndInsert("Release checklist", used: Self.note.id))
    }

    /// A clip with no rich form has always pasted plain, and the modifier must not make
    /// that a different code path with a different set of bugs.
    @Test("on a clip with no formatting the two are the same")
    func noDifferenceWithoutFormatting() {
        let ordinary = Self.panel([Self.plain])

        #expect(
            ordinary.applying(.return).outcome.effect
                == ordinary.applying(.returnPlain).outcome.effect)
    }

    @Test("⌘-click is ⌘⏎ on the row under the pointer")
    func commandClickMatches() {
        let panel = Self.panel([Self.plain, Self.note])

        #expect(
            panel.applying(.choosePlain(Self.note.id)).outcome
                == panel.applying([.choose(Self.note.id)]).state.applying(.returnPlain).outcome)
    }

    /// Only the formatting differs. Whether the words land at all is the same question,
    /// so ⌘ on a machine with no caret still copies and still says so.
    @Test("the modifier does not skip the copy-only path")
    func stillReportsWhenItCannotPlace() {
        var panel = Self.panel([Self.note])
        panel.insertion = .clipboardOnly(.nothingFocused)

        guard case .copyAndSay(let text, let notice, _) = panel.applying(.returnPlain).outcome.effect
        else {
            Issue.record("⌘⏎ went silent where ⏎ would have spoken")
            return
        }
        #expect(text == "Release checklist")
        #expect(!notice.message.isEmpty)
    }

    /// The sheet owns Return while it is open, and the modifier must not be a way round
    /// that — ⌘⏎ behind a half-typed alias would paste the clip being named.
    @Test("a sheet still owns Return, modifier or not")
    func theSheetStillWins() {
        let naming = Self.panel([Self.note]).applying(.alias(Self.note.id)).state

        if case .insertPlain = naming.applying(.returnPlain).outcome {
            Issue.record("⌘⏎ pasted from behind an open sheet")
        }
    }
}
