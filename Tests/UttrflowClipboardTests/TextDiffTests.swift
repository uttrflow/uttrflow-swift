// Tests for the formatter diff.

import Testing

@testable import UttrflowClipboard

/// A formatter is a program the user did not write running over code they did.
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

    /// A longest-common-subsequence diff, because an inserted line must not report the whole file as changed.
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

    /// Long runs of untouched code make a diff unreadable and are not what anybody decides about.
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

    /// Reindenting shows every touched line as a pair, which is why the count leads.
    @Test("reindentation shows as a pair per line, and is counted honestly")
    func reindent() {
        let before = "func a() {\nlet x = 1\n}"
        let after = "func a() {\n    let x = 1\n}"

        #expect(TextDiff.changedLines(from: before, to: after) == 2)
    }
}

@Suite("D6 · the formatter diff in bounded time and memory")
struct TextDiffScalingTests {
    /// The steps one guarded comparison takes.
    private static func steps(from before: String, to after: String) -> Int {
        let tally = DiffTally()
        TextDiff.$tally.withValue(tally) { _ = TextDiff.compare(from: before, to: after) }
        return tally.count
    }

    /// A text of distinct numbered lines, with every `every`th one indented.
    private static func text(lines: Int, indentingEvery every: Int = 0) -> String {
        (0..<lines).map { every > 0 && $0 % every == every - 1 ? "    line \($0) {" : "line \($0) {" }
            .joined(separator: "\n")
    }

    @Test("A few changed lines cost steps in proportion to the text, not to its square")
    func fewChangesCostLinearWork() {
        let small = Self.steps(
            from: Self.text(lines: 1_000), to: Self.text(lines: 1_000, indentingEvery: 250))
        let large = Self.steps(
            from: Self.text(lines: 10_000), to: Self.text(lines: 10_000, indentingEvery: 2_500))

        #expect(small > 0 && large > 0, "the tally must be connected")
        #expect(small <= 20 * 1_000, "1,000 lines took \(small) steps")
        #expect(large <= 20 * 10_000, "10,000 lines took \(large) steps")
    }

    @Test("A pair past the change limit stops looking, having spent at most the limit's work")
    func manyChangesStopAtTheLimit() {
        let lines = TextDiff.changeLimit
        let before = Self.text(lines: lines)
        let after = Self.text(lines: lines, indentingEvery: 1)
        let limit = TextDiff.changeLimit

        #expect(TextDiff.compare(from: before, to: after) == .tooLarge(before: lines, after: lines))
        let steps = Self.steps(from: before, to: after)
        #expect(steps > 0)
        #expect(steps <= limit * limit + 4 * lines)
    }

    @Test("A pair past the line or byte limit is refused before any diff is taken")
    func sizeLimitsRefuseUpFront() {
        let long = Array(repeating: "x", count: TextDiff.lineLimit + 1).joined(separator: "\n")
        let wide = String(repeating: "x", count: TextDiff.byteLimit + 1)

        #expect(TextDiff.compare(from: long, to: "x") == .tooLarge(before: TextDiff.lineLimit + 1, after: 1))
        #expect(TextDiff.compare(from: "x", to: wide) == .tooLarge(before: 1, after: 1))
        #expect(Self.steps(from: long, to: "x") == 0)
    }

    @Test("A pair inside every limit is compared line by line")
    func smallPairsAreCompared() {
        #expect(
            TextDiff.compare(from: "a\nb", to: "a\nc")
                == .lines([
                    .init(kind: .same, text: "a"), .init(kind: .removed, text: "b"),
                    .init(kind: .added, text: "c"),
                ]))
    }

    @Test("Every small pair gets the same lines as the full table, and the fewest changes")
    func agreesWithTheTable() {
        var random = DiffSeeded(seed: 406)
        for _ in 0..<20_000 {
            let alphabet = Array(["a", "b", "c", ""].prefix(Int.random(in: 1...4, using: &random)))
            let before = (0..<Int.random(in: 0...10, using: &random)).map { _ in
                alphabet.randomElement(using: &random) ?? ""
            }
            let after = (0..<Int.random(in: 0...10, using: &random)).map { _ in
                alphabet.randomElement(using: &random) ?? ""
            }
            let old = before.joined(separator: "\n")
            let new = after.joined(separator: "\n")
            let lines = TextDiff.lines(from: old, to: new)
            let table = TableDiff.lines(from: old, to: new)

            #expect(lines == table.lines, "\(old.debugDescription) → \(new.debugDescription)")
            #expect(TextDiff.changedLines(in: lines) == table.fewestChanges)
            #expect(
                lines.filter { $0.kind != .added }.map(\.text)
                    == old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            #expect(
                lines.filter { $0.kind != .removed }.map(\.text)
                    == new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        }
    }

    @Test("Interesting lines are the changes and their context, in order")
    func interestingKeepsOrder() {
        let all: [TextDiff.Line] = ["a", "b", "c", "d", "e", "f"].enumerated().map { index, text in
            .init(kind: index == 0 || index == 4 ? .added : .same, text: text)
        }

        #expect(TextDiff.interesting(in: all).map(\.text) == ["a", "b", "d", "e", "f"])
        #expect(TextDiff.interesting(in: all, context: 0).map(\.text) == ["a", "e"])
        #expect(TextDiff.interesting(in: all, context: -1).map(\.text) == ["a", "e"])
        #expect(TextDiff.interesting(in: []).isEmpty)
    }
}

/// A fixed-seed generator, so every generated pair is the same on every run.
private struct DiffSeeded: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) { state = (UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15) | 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// The full longest-common-subsequence table the linear-space diff replaced, kept as its oracle.
private enum TableDiff {
    static func lines(from before: String, to after: String) -> (lines: [TextDiff.Line], fewestChanges: Int) {
        let old = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let new = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var common = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                common[i][j] =
                    old[i] == new[j] ? common[i + 1][j + 1] + 1 : max(common[i + 1][j], common[i][j + 1])
            }
        }
        var result: [TextDiff.Line] = []
        var i = 0
        var j = 0
        while i < old.count && j < new.count {
            if old[i] == new[j] {
                result.append(.init(kind: .same, text: old[i]))
                i += 1
                j += 1
            } else if common[i + 1][j] >= common[i][j + 1] {
                result.append(.init(kind: .removed, text: old[i]))
                i += 1
            } else {
                result.append(.init(kind: .added, text: new[j]))
                j += 1
            }
        }
        result += old[i...].map { .init(kind: .removed, text: $0) }
        result += new[j...].map { .init(kind: .added, text: $0) }
        return (result, old.count + new.count - 2 * common[0][0])
    }
}

/// Text copied from another system ends its lines in CRLF or CR, and a line is still a line.
@Suite("D6 · line endings other than LF")
struct TextDiffLineEndingTests {
    private func rows(_ comparison: TextDiff.Comparison) -> [TextDiff.Line] {
        guard case .lines(let rows) = comparison else { return [] }
        return rows
    }

    @Test("text in any ending keeps its unchanged lines", arguments: ["\n", "\r\n", "\r"])
    func unchangedLinesSurvive(_ ending: String) {
        let before = ["one", "two", "three"].joined(separator: ending)
        let after = ["one", "changed", "three"].joined(separator: ending)
        #expect(
            rows(TextDiff.compare(from: before, to: after)) == [
                .init(kind: .same, text: "one"), .init(kind: .removed, text: "two"),
                .init(kind: .added, text: "changed"), .init(kind: .same, text: "three"),
            ])
    }

    @Test("a trailing ending makes an empty last line whatever the ending", arguments: ["\n", "\r\n", "\r"])
    func trailingEnding(_ ending: String) {
        #expect(
            rows(TextDiff.compare(from: "one", to: "one\(ending)")) == [
                .init(kind: .same, text: "one"), .init(kind: .added, text: ""),
            ])
    }

    @Test("mixed endings split at each of them")
    func mixedEndings() {
        let text = "a\nb\r\nc\rd"
        #expect(rows(TextDiff.compare(from: text, to: text)).map(\.text) == ["a", "b", "c", "d"])
    }

    @Test("changing only the line endings is a change on every line that ended differently")
    func endingsOnlyAreAChange() {
        let comparison = TextDiff.compare(from: "one\r\ntwo\r\nthree", to: "one\ntwo\nthree")
        #expect(TextDiff.changedLines(in: rows(comparison)) == 4)
        #expect(rows(comparison).first == .init(kind: .same, text: "one"))
    }

    @Test("the line limit counts CRLF and CR lines", arguments: ["\r\n", "\r"])
    func lineLimitCountsEveryEnding(_ ending: String) {
        let long = Array(repeating: "x", count: TextDiff.lineLimit + 1).joined(separator: ending)
        #expect(TextDiff.compare(from: long, to: "x") == .tooLarge(before: TextDiff.lineLimit + 1, after: 1))
    }

    @Test("the byte limit's line count agrees with the split", arguments: ["\n", "\r\n", "\r"])
    func byteLimitCountAgrees(_ ending: String) {
        let lines = TextDiff.byteLimit / 2 + 1
        let long = Array(repeating: "x", count: lines).joined(separator: ending)
        #expect(TextDiff.compare(from: long, to: "a\r\nb\nc") == .tooLarge(before: lines, after: 3))
    }
}
