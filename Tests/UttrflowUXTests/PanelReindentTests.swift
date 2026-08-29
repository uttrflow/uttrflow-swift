import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// D4 — the one action here that rewrites what was copied, so the tests are mostly about
/// when it is *not* offered.
@Suite("D4 · offering to tidy indentation")
struct PanelReindentTests {
    static let messy = Clip(
        text: "func a() {\n\tlet x = 1\n        let y = 2\n}", kind: .code,
        copiedAt: PanelFixture.now, language: .swift)

    static func actions(_ clip: Clip) -> [String] {
        PanelPresenter.present(PanelFixture.panel([clip])).rows[0].actions.map(\.title)
    }

    /// The presence of the action is itself the promise that pressing it is safe: it is
    /// drawn only where the re-indenter has already decided it can act.
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

    /// Prose has no indentation to be wrong, and offering to tidy a paragraph would
    /// suggest the app is going to rewrite it.
    @Test("never offered on anything that is not code")
    func neverOnProse() {
        for kind in ClipKind.allCases where kind != .code {
            let clip = Clip(
                text: "one\n\ttwo\n        three", kind: kind, copiedAt: PanelFixture.now)
            #expect(!Self.actions(clip).contains("Re-indent"), "\(kind)")
        }
    }

    /// Inside a multi-line string leading whitespace is content, and the re-indenter
    /// refuses those. The row must not offer what the model would decline.
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
