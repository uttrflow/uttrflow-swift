// Tests for what the app does about a panel outcome, and that every choice reports which clip.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The decisions `AppDelegate` is not allowed to hold, since it is excluded from the coverage gate.
@Suite("What the app does about a panel keystroke")
struct PanelEffectTests {
    @Test("a key that only moved the highlight redraws, and nothing else")
    func stillOpen() {
        #expect(PanelOutcome.open.effect == .redraw)
    }

    @Test("escape closes and changes nothing")
    func dismissed() {
        #expect(PanelOutcome.dismissed.effect == .close)
    }

    /// A panel still on screen after the third keystroke is a fourth, and it hides the pasted text.
    @Test("choosing a clip closes the panel as well as inserting")
    func insertingCloses() {
        let clip = PanelFixture.clip("hello")
        let effect = PanelOutcome.insert(clip).effect

        #expect(effect == .closeAndInsert("hello", used: clip.id))
        #expect(effect != .redraw, "the panel does not stay up")
    }

    /// Pasting what the row drew would truncate the clip, and a wrong-string paste still reports success.
    @Test("a multi-line clip inserts every line, not the line the row drew")
    func insertsEveryLine() {
        let clip = PanelFixture.clip("first\nsecond\nthird")

        #expect(clip.summary == "first", "the row really does draw only the first line")
        #expect(
            PanelOutcome.insert(clip).effect
                == .closeAndInsert("first\nsecond\nthird", used: clip.id))
    }

    /// Masking is for the screen; the clip is still the token, and pasting bullets looks like success.
    @Test("a masked secret inserts the secret, not the bullets")
    func insertsBehindTheMask() {
        let secret = PanelFixture.clip("sk-live-abcdef123456", kind: .secret)

        let drawn = PanelPresenter.present(PanelFixture.panel([secret])).rows[0]
        #expect(drawn.isMasked, "the row is masked")
        #expect(!drawn.summary.contains("sk-live"), "and really does not show it")

        #expect(
            PanelOutcome.insert(secret).effect
                == .closeAndInsert("sk-live-abcdef123456", used: secret.id))
    }

    /// Whitespace is content: indentation is the whole value of copying a block of code.
    @Test("nothing is trimmed on the way out")
    func nothingTrimmed() {
        let padded = PanelFixture.clip("    indented\n\n")

        #expect(
            PanelOutcome.insert(padded).effect
                == .closeAndInsert("    indented\n\n", used: padded.id))
    }
}

/// Every way of choosing a clip says which clip, since eviction ranks by ``Clip/lastUsedAt``.
@Suite("Choosing a clip says which clip")
struct PanelUseReportingTests {
    /// A plain clip.
    static let clip = PanelFixture.clip("the words")
    /// Another plain clip.
    static let note = PanelFixture.clip("a note")

    /// A panel over these clips with this insertion answer.
    static func panel(_ insertion: PanelInsertion, _ clips: [Clip] = [clip]) -> PanelSnapshot {
        var snapshot = PanelFixture.panel(clips)
        snapshot.insertion = insertion
        return snapshot
    }

    /// The identity a given effect reports, or `nil` where it reports none.
    static func used(of effect: PanelEffect) -> Clip.ID? {
        switch effect {
        case .closeAndInsert(_, let used): used
        case .closeAndInsertFormatted(_, _, let used): used
        case .copyAndSay(_, _, let used): used
        case .closeAndInsertImage(let clip): clip.id
        case .redraw, .close, .applyAndRedraw, .say: nil
        }
    }

    @Test(
        "whatever the machine's state, the clip that was chosen is the clip reported",
        arguments: [PanelInsertion.atCaret]
            + PanelInsertionObstacle.allCases.map(PanelInsertion.clipboardOnly))
    func everyOutcomeReportsTheClip(insertion: PanelInsertion) {
        let effect = Self.panel(insertion).applying(.return).outcome.effect

        #expect(
            Self.used(of: effect) == Self.clip.id,
            "a paste that does not say which clip it pasted leaves that clip's clock stopped")
    }

    /// ⌘⏎ takes a different route through the outcome, so it is checked on its own.
    @Test("and the plain-paste route reports it too")
    func plainPasteReportsTheClip() {
        let formatted = Clip(
            text: "Release checklist", kind: .text, copiedAt: PanelFixture.now,
            richText: "<h1>Release checklist</h1>")

        let rich = Self.panel(.atCaret, [formatted]).applying(.return).outcome.effect
        let plain = Self.panel(.atCaret, [formatted]).applying(.returnPlain).outcome.effect

        #expect(Self.used(of: rich) == formatted.id)
        #expect(Self.used(of: plain) == formatted.id)
    }

    /// Choosing by mouse is the same promise by a different gesture.
    @Test("clicking a row reports it as surely as Return does")
    func clickingReportsTheClip() {
        let effect = Self.panel(.atCaret).applying(.choose(Self.clip.id)).outcome.effect

        #expect(Self.used(of: effect) == Self.clip.id)
    }

    /// Merely looking is not using, or the order would record scrolling rather than reaching.
    @Test("but arrowing past a row is not using it")
    func browsingIsNotUsing() {
        let clips = [Self.clip, Self.note]
        let effect = Self.panel(.atCaret, clips).applying([.down, .up]).outcome.effect

        #expect(Self.used(of: effect) == nil)
        #expect(effect == .redraw)
    }
}
