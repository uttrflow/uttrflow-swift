// Tests for offering to re-indent a code clip, and for what choosing it changes.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The one action that rewrites what was copied, so the tests are mostly about when it is not offered.
@Suite("D4 · offering to tidy indentation")
struct PanelReindentTests {
    /// Code with mixed tabs and spaces.
    static let messy = Clip(
        text: "func a() {\n\tlet x = 1\n        let y = 2\n}", kind: .code,
        copiedAt: PanelFixture.now, language: .swift)

    /// The row's action titles for one clip.
    static func actions(_ clip: Clip) -> [String] {
        PanelPresenter.present(PanelFixture.panel([clip])).rows[0].actions.map(\.title)
    }

    /// The action's presence is the promise that pressing it is safe: drawn only where it can act.
    @Test("offered on a code clip whose indentation can be tidied")
    func offeredWhenItWouldHelp() {
        #expect(Self.actions(Self.messy).contains("Re-indent"))
    }

    @Test("not offered on code that is already consistent")
    func notOfferedWhenTidy() {
        let tidy = Clip(
            text: "func a() {\n    let x = 1\n    let y = 2\n}", kind: .code,
            copiedAt: PanelFixture.now)

        #expect(!Self.actions(tidy).contains("Re-indent"))
    }

    /// Prose has no indentation to be wrong, and offering to tidy a paragraph suggests a rewrite.
    @Test("never offered on anything that is not code")
    func neverOnProse() {
        for kind in ClipKind.allCases where kind != .code {
            let clip = Clip(
                text: "one\n\ttwo\n        three", kind: kind, copiedAt: PanelFixture.now)
            #expect(!Self.actions(clip).contains("Re-indent"), "\(kind)")
        }
    }

    /// Whitespace inside a multi-line string is content, so the row does not offer what the model refuses.
    @Test("not offered where the re-indenter would refuse")
    func notOfferedWhenUnsafe() {
        let literal = Clip(
            text: "let s = \"\"\"\n\thello\n        there\n\"\"\"", kind: .code,
            copiedAt: PanelFixture.now)

        #expect(CodeReindent.reindented(literal.text) == nil, "the re-indenter refuses this")
        #expect(!Self.actions(literal).contains("Re-indent"), "so the row does not offer it")
    }

    @Test("choosing it asks the store for the tidied text and nothing else")
    func itChangesOnlyTheText() {
        let response = PanelFixture.panel([Self.messy]).applying(.reindent(Self.messy.id))

        guard case .change(.rewriteText(let id, let tidied)) = response.outcome else {
            Issue.record("did not ask for a re-indent")
            return
        }
        #expect(id == Self.messy.id)
        // The guarantee the re-indenter makes, checked again at the seam where it is used.
        let before = Self.messy.text.split(separator: "\n", omittingEmptySubsequences: false)
        let after = tidied.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before.count == after.count, "no line added or lost")
        #expect(
            before.map { $0.drop { $0 == " " || $0 == "\t" } }
                == after.map { $0.drop { $0 == " " || $0 == "\t" } },
            "every line's content is untouched")
    }

    /// A clip can change between the row being drawn and the button being pressed.
    @Test("asked again at the moment it acts, not trusted from the row")
    func rechecksOnUse() {
        let tidy = Clip(
            text: "func a() {\n    let x = 1\n}", kind: .code, copiedAt: PanelFixture.now)

        #expect(PanelFixture.panel([tidy]).applying(.reindent(tidy.id)).outcome == .open)
        #expect(PanelFixture.panel([]).applying(.reindent(tidy.id)).outcome == .open)
    }
}

/// Whether a clip can be re-indented is asked once per text, never again on each keystroke.
@Suite("D4 · offering re-indent costs nothing per keystroke")
struct PanelReindentCostTests {
    /// Code clips that are each worth offering Re-indent for.
    static let codeClips = (0..<5).map { index in
        Clip(
            text: "func f\(index)() {\n\tlet x = 1\n        let y = 2\n}", kind: .code,
            copiedAt: PanelFixture.now)
    }

    /// How many re-indents `work` ran.
    static func reindents(_ work: () -> Void) -> Int {
        let tally = ReindentTally()
        CodeReindent.$tally.withValue(tally) { work() }
        return tally.count
    }

    @Test("arrowing, typing and redrawing re-indent nothing once the panel is drawn")
    func keystrokesDoNotReindent() {
        let opened = PanelFixture.panel(Self.codeClips)
        #expect(Self.reindents { _ = PanelPresenter.present(opened) } == Self.codeClips.count)

        let arrowed = opened.applying(.down).state
        let typed = arrowed.applying(.search("f")).state
        let later = Self.reindents {
            for snapshot in [opened, arrowed, typed] {
                let rows = PanelPresenter.present(snapshot).rows
                #expect(rows.allSatisfy { $0.actions.contains { $0.title == "Re-indent" } })
            }
        }
        #expect(later == 0)
    }

    @Test("a clip whose text is rewritten is asked again, once")
    func rewrittenTextIsAskedAgain() {
        var snapshot = PanelFixture.panel(Self.codeClips)
        _ = PanelPresenter.present(snapshot)
        let first = Self.codeClips[0]
        let tidied = Clip(
            id: first.id, text: "func f0() {\n    let x = 1\n    let y = 2\n}", kind: .code,
            copiedAt: first.copiedAt)
        snapshot.clips[0] = tidied

        var rows: [PanelRow] = []
        #expect(Self.reindents { rows = PanelPresenter.present(snapshot).rows } == 1)
        #expect(!rows[0].actions.contains { $0.title == "Re-indent" })
        #expect(rows[1].actions.contains { $0.title == "Re-indent" })
    }
}
