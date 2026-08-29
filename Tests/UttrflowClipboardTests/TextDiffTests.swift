import Testing

@testable import UttrflowClipboard

/// D6 — a formatter is a program the user did not write running over code they did, so
/// "here is what it wants to do" is the difference between a tool and a surprise.
@Suite("D6 · what the formatter wants to change")
struct TextDiffTests {
    @Test("identical text has nothing to show")
    func noChange() {
        let same = "let a = 1\nlet b = 2"

        #expect(TextDiff.changedLines(from: same, to: same) == 0)
        #expect(TextDiff.interesting(from: same, to: same).isEmpty)
        #expect(TextDiff.lines(from: same, to: same).allSatisfy { $0.kind == .same })
    }

    @Test("a changed line reads as one removal and one addition")
    func oneLineChanged() {
        let lines = TextDiff.lines(from: "let a=1\nlet b = 2", to: "let a = 1\nlet b = 2")

        #expect(lines.count { $0.kind == .removed } == 1)
        #expect(lines.count { $0.kind == .added } == 1)
        #expect(lines.count { $0.kind == .same } == 1)
    }

    /// The reason this is a longest-common-subsequence diff rather than a positional
    /// comparison. Inserting one line at the top shifts every line after it, and a naïve
    /// diff reports the whole file as changed — useless for deciding whether to accept.
    @Test("inserting a line does not report every line after it as changed")
    func insertionDoesNotCascade() {
        let before = "one\ntwo\nthree\nfour"
        let after = "zero\none\ntwo\nthree\nfour"

        #expect(TextDiff.changedLines(from: before, to: after) == 1)
        #expect(TextDiff.lines(from: before, to: after).count { $0.kind == .same } == 4)
    }

    @Test("a deleted line is reported as one removal")
    func deletion() {
        let lines = TextDiff.lines(from: "one\ntwo\nthree", to: "one\nthree")

        #expect(lines.count { $0.kind == .removed } == 1)
        #expect(lines.first { $0.kind == .removed }?.text == "two")
    }

    /// Long runs of untouched code are what make a diff unreadable in a narrow panel, and
    /// they are also the part nobody is deciding about.
    @Test("only the changed parts are offered, with context around them")
    func interestingIsShort() {
        let before = (1...40).map { "line \($0)" }.joined(separator: "\n")
        let after = before.replacingOccurrences(of: "line 20", with: "line twenty")

        let shown = TextDiff.interesting(from: before, to: after)

        #expect(shown.count < 10, "forty lines in, a handful out")
        #expect(shown.contains { $0.text == "line twenty" && $0.kind == .added })
        #expect(shown.contains { $0.text == "line 20" && $0.kind == .removed })
        #expect(shown.contains { $0.kind == .same }, "with a line of context")
    }

    @Test("everything replaced reads as everything replaced")
    func whollyDifferent() {
        let lines = TextDiff.lines(from: "a\nb", to: "c\nd")

        #expect(lines.count { $0.kind == .same } == 0)
        #expect(lines.count { $0.kind == .removed } == 2)
        #expect(lines.count { $0.kind == .added } == 2)
    }

    @Test("empty on either side does not crash")
    func empties() {
        #expect(TextDiff.lines(from: "", to: "").allSatisfy { $0.kind == .same })
        #expect(TextDiff.changedLines(from: "", to: "a") == 2, "one blank out, one line in")
        #expect(TextDiff.changedLines(from: "a", to: "") == 2)
    }

    /// Reindenting is the commonest thing a formatter does, and every touched line shows
    /// as a pair — which is why the count leads rather than the lines themselves.
    @Test("reindentation shows as a pair per line, and is counted honestly")
    func reindent() {
        let before = "func a() {\nlet x = 1\n}"
        let after = "func a() {\n    let x = 1\n}"

        #expect(TextDiff.changedLines(from: before, to: after) == 2)
    }
}
