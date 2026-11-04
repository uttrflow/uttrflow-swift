// Tests for the one replaced word range between inserted text and what the person left.

import Testing

@testable import UttrflowDictionary

@Suite("Observed edits")
struct ObservedEditTests {
    private func edit(_ inserted: String, _ left: String) -> ObservedEdit? {
        ObservedEdit.between(inserted: inserted, left: left)
    }

    @Test("A one-word replacement is one edit")
    func oneWordReplace() {
        #expect(
            edit("run gate push now", "run git push now")
                == ObservedEdit(heard: ["gate"], wrote: ["git"], position: 1))
    }

    @Test("A two-word replacement is one edit")
    func twoWordReplace() {
        #expect(
            edit("open the cube control docs", "open the kubectl docs")
                == ObservedEdit(heard: ["cube", "control"], wrote: ["kubectl"], position: 2))
    }

    @Test("A case-only change is not an edit")
    func caseOnly() {
        #expect(edit("run git push", "Run Git push") == nil)
    }

    @Test(
        "Insertions, deletions, rewrites and moved clauses yield nothing",
        arguments: [
            ("run git push now", "run git push now please"),
            ("run git push now please", "run git push now"),
            ("run git push now", "totally different words are here today"),
            ("call me after lunch about the budget", "about the budget call me after lunch"),
            ("run gate push now", "launch git push soon"),
            ("x y", "y x"),
            ("one two three four five six seven", "one 2 three four 5 six seven"),
        ])
    func yieldsNothing(inserted: String, left: String) {
        #expect(edit(inserted, left) == nil)
    }

    @Test(
        "Aligning a text with itself yields no edit",
        arguments: [
            "", "hello", "run git push now", "a b c d e f g h i j",
        ])
    func selfAlignment(_ text: String) {
        #expect(edit(text, text) == nil)
    }
}
