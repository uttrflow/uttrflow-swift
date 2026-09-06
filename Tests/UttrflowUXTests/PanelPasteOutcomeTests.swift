// Tests for what choosing a clip does when it cannot be placed, and for a write the disk refused.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The one forbidden outcome is a panel that closes having done nothing; these are the states near it.
@Suite("B1–B5 · what choosing a clip actually does")
struct PanelPasteOutcomeTests {
    /// A plain clip.
    static let clip = PanelFixture.clip("the words", minutesAgo: 1)

    /// A panel over the clip with this insertion answer.
    static func panel(_ insertion: PanelInsertion) -> PanelSnapshot {
        var snapshot = PanelFixture.panel([Self.clip])
        snapshot.insertion = insertion
        return snapshot
    }

    /// The two that succeed are indistinguishable to the user: the text appearing is the confirmation.
    @Test("B1, B2 · when it can place the text, it places it and closes")
    func placesAndCloses() {
        let response = Self.panel(.atCaret).applying(.return)

        #expect(response.outcome == .insert(Self.clip))
        #expect(response.outcome.effect == .closeAndInsert("the words", used: Self.clip.id))
    }

    /// B4 — there is no caret to insert at, and saying so beats a silent no-op.
    @Test("B4 · with nothing focused, it copies and says where the words went")
    func nothingFocused() {
        let response = Self.panel(.clipboardOnly(.nothingFocused)).applying(.return)

        guard case .copyAndSay(let text, let notice, let used) = response.outcome.effect else {
            Issue.record("did not report the copy")
            return
        }
        #expect(text == "the words")
        #expect(used == Self.clip.id, "and says which clip, so its use is recorded")
        #expect(notice.message.contains("⌘V"))
        #expect(notice.action == nil, "nothing to fix — there is simply no caret")
    }

    /// B5 — the same copy, but this one has a cause the user can remove.
    @Test("B5 · without Accessibility it copies, explains, and offers the fix")
    func noAccessibility() {
        let response = Self.panel(.clipboardOnly(.accessibilityNotGranted)).applying(.return)

        guard case .copyAndSay(_, let notice, _) = response.outcome.effect else {
            Issue.record("did not report the copy")
            return
        }
        #expect(notice.message.contains("⌘V"))
        #expect(notice.action?.intent == .openAccessibilitySettings)
    }

    /// The forbidden outcome as a test, over every obstacle in `allCases` so a new one cannot slip past.
    @Test(
        "choosing a clip is never silent and never a no-op",
        arguments: [PanelInsertion.atCaret]
            + PanelInsertionObstacle.allCases.map(PanelInsertion.clipboardOnly))
    func neverSilent(insertion: PanelInsertion) {
        let effect = Self.panel(insertion).applying(.return).outcome.effect

        switch effect {
        case .closeAndInsert(let text, _), .closeAndInsertFormatted(let text, _, _):
            #expect(!text.isEmpty)
        case .copyAndSay(let text, let notice, _):
            #expect(!text.isEmpty)
            #expect(!notice.message.isEmpty, "copied, and said so")
        case .closeAndInsertImage(let clip):
            #expect(clip.image != nil)
        case .say(let notice):
            // B8 — there was nothing to paste, and the panel says exactly that.
            #expect(!notice.message.isEmpty)
        case .redraw, .close, .applyAndRedraw:
            Issue.record("choosing a clip did nothing the user can see")
        }
    }

    /// Calling a copy an insertion is how "it did nothing" gets reported as a success.
    @Test("a copy is never reported as an insertion")
    func aCopyIsNotAnInsertion() {
        let effect = Self.panel(.clipboardOnly(.nothingFocused)).applying(.return).outcome.effect

        #expect(effect != .closeAndInsert("the words", used: Self.clip.id))
    }

    /// The obstacle is settled when the panel opens, so a click and Return cannot disagree.
    @Test("a click reports the same outcome as Return")
    func clickAgreesWithReturn() {
        let panel = Self.panel(.clipboardOnly(.nothingFocused))

        #expect(panel.applying(.choose(Self.clip.id)).outcome == panel.applying(.return).outcome)
    }
}

/// F10 — a write the disk refused has to look different from one that succeeded.
@Suite("F10 · the disk refused the change")
struct PanelWriteFailureTests {
    @Test("the notice carries the reason and offers no false fix")
    func saysWhy() {
        let notice = PanelNotice.writeFailed("The clipboard could not be saved.")

        #expect(notice.message == "The clipboard could not be saved.")
        #expect(notice.action == nil, "there is nothing the user can press to fix a full disk")
    }

    /// A failed write must be visible: a sheet that closes and changes nothing looks like success.
    @Test("it is not dressed as the copy notices, which are not failures")
    func itLooksLikeAProblem() {
        let failure = PanelNotice.writeFailed("x")
        let copied = PanelInsertionObstacle.nothingFocused.notice

        #expect(failure.symbolName != copied.symbolName)
        #expect(failure.symbolName.contains("exclamationmark"))
    }

    /// Each obstacle has its own way out, so one shared sentence would send people to the wrong fix.
    @Test("every obstacle says something, and no two say the same thing")
    func everyObstacleSpeaksForItself() {
        let notices = PanelInsertionObstacle.allCases.map(\.notice)

        for notice in notices {
            #expect(!notice.message.isEmpty)
            #expect(!notice.symbolName.isEmpty)
        }
        #expect(Set(notices.map(\.message)).count == notices.count)
    }

    /// Uttrflow's own window in front is not "nothing is focused"; a cursor may be blinking behind it.
    @Test("being in front is told apart from having nothing focused")
    func inFrontIsItsOwnThing() {
        let inFront = PanelInsertionObstacle.uttrflowInFront.notice
        let nothing = PanelInsertionObstacle.nothingFocused.notice

        #expect(inFront.message != nothing.message)
        #expect(inFront.message.lowercased().contains("click"))
    }
}
