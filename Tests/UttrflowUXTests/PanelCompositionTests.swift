// Tests which keys the panel gives up while an input method is composing a word.
import Testing

@testable import UttrflowClipboard
@testable import UttrflowUX

/// Committing a word in Japanese, Chinese, Korean or transliterated Hindi is a Return the panel must not take.
@Suite("The keys an input method owns while it composes")
struct PanelCompositionTests {
    /// Return commits the candidate, the arrows walk the candidate list, and Escape cancels the word.
    @Test(
        "gives up Return, the arrows and Escape mid-composition",
        arguments: [PanelKey.return, .returnPlain, .up, .down, .escape])
    func givenToTheInputMethod(_ key: PanelKey) {
        #expect(!PanelComposition.panelMayTake(key, whileComposing: true))
    }

    /// The same keys are the panel's whenever no composition is open, which is all Latin typing.
    @Test(
        "keeps them all when nothing is being composed",
        arguments: [PanelKey.return, .returnPlain, .up, .down, .escape])
    func keptWhenNotComposing(_ key: PanelKey) {
        #expect(PanelComposition.panelMayTake(key, whileComposing: false))
    }

    /// The long navigation keys are intercepted before the normal chord resolver.
    @Test("gives Page Up, Page Down, Home and End to the input method")
    func navigationJumpsBelongToTheInputMethod() {
        let jumps: [PanelKey] = [
            .jump(.pageUp), .jump(.pageDown), .jump(.top), .jump(.bottom),
        ]

        #expect(jumps.allSatisfy { !PanelComposition.panelMayTake($0, whileComposing: true) })
        #expect(jumps.allSatisfy { PanelComposition.panelMayTake($0, whileComposing: false) })
    }

    /// The chord resolver returns intents directly, bypassing `send`; they still belong to the IME.
    @Test("gives command chord intents to the input method")
    func commandChordBelongsToTheInputMethod() {
        let chord = PanelKeyDecision.intent(.undoDelete)

        #expect(!PanelComposition.panelMayTake(chord, whileComposing: true))
        #expect(PanelComposition.panelMayTake(chord, whileComposing: false))
    }

    /// A committed word still has to reach the query, or the list never filters for these scripts.
    @Test("keeps the text a composition commits")
    func committedTextStillReachesThePanel() {
        #expect(PanelComposition.panelMayTake(.search("日本"), whileComposing: true))
        #expect(PanelComposition.panelMayTake(.draft("नमस्ते"), whileComposing: true))
        #expect(!PanelComposition.panelMayTake(.key(.clearSearch), whileComposing: true))
        #expect(PanelComposition.panelMayTake(.key(.clearSearch), whileComposing: false))
        #expect(!PanelComposition.panelMayTake(.key(.showShortcuts), whileComposing: true))
        #expect(PanelFixture.panel([], query: "needle").applying(.clearSearch).state.query.isEmpty)
    }

    /// A chip is not a key any input method is waiting for; collection numbers are command chords.
    @Test("keeps the keys an input method never claims")
    func keysAnInputMethodNeverClaims() {
        let mine: [PanelKey] = [.filter(.images), .scope(.pinned), .search("a")]

        #expect(mine.allSatisfy { PanelComposition.panelMayTake($0, whileComposing: true) })
        #expect(!PanelComposition.panelMayTake(.category(number: 3), whileComposing: true))
    }

    /// A click is not a keystroke, so a composition open in the field never stops one landing.
    @Test("keeps what the pointer asks for, whatever the field is doing")
    func thePointerIsNeverComposing() {
        let id = Clip(text: "one", kind: .text, copiedAt: .now).id
        let byPointer: [PanelKey] = [.choose(id), .choosePlain(id), .reveal(id), .delete(id)]

        #expect(byPointer.allSatisfy { PanelComposition.panelMayTake($0, whileComposing: true) })
    }
}
