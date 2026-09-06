import Testing

@testable import UttrflowLocalModel

/// Words a line might be made of, none of which forms one of the prompt's own headings.
private let words = [
    "git", "commit", "checkout", "main", "ls", "-la", "docker", "compose", "up", "select", "from", "users",
    "where", "kal", "milenge", "bhai", "chai", "peene", "chalo", "on", "my", "way", "running", "late",
    "sorry",
    "🙏", "😂", "🚀", "नमस्ते", "ठीक", "MitoActive™", "Acme®", "Café", "naïve", "e\u{301}clair", "price", "of",
    "serum", "and", "is", "in", "stock?", "deploy", "release", "candidate", "12", "3.5", "x.y()",
]

/// The marks a model drops or adds when it repeats a line, which never decide whether it repeated it.
private let marks = Array(MLXCandidateScorer.ignoredMarks).map(String.init).sorted()

/// One reply the model might give and what parsing it must come to, built from a seed.
struct ParseCase: Sendable, CustomTestStringConvertible {
    let seed: Int
    let typed: String
    let response: String
    /// The lines that must come out, in order, kept by the generator as it wrote each line.
    let expected: [String]

    init(seed: Int) {
        var random = Seeded(seed: seed)
        self.seed = seed
        let typed = ParseCase.typed(&random)
        self.typed = typed
        var lines: [String] = []
        var expected: [String] = []
        for _ in 0..<Int.random(in: 1...7, using: &random) {
            var line: String
            var whole: String?
            switch Int.random(in: 0..<10, using: &random) {
            case 0:
                line = random.pick(["```", "```bash", "``` "])
            case 1:
                // A line two stray characters away from beginning with what was typed, which no single slip explains.
                line = "§§" + typed + " more"
            case 2:
                // A strict opening of the typed text, which continues nothing.
                line = String(typed.dropLast(Int.random(in: 1...typed.count, using: &random)))
            case 3:
                line = ParseCase.echo(of: typed, &random)
            default:
                let continuation = ParseCase.continuation(&random)
                line = ParseCase.echo(of: typed, &random) + continuation
                if ParseCase.isUsable(continuation, on: line) { whole = typed + continuation }
            }
            if random.chance(0.4) { line = random.pick(["- ", "* ", "• ", "1. ", "7. ", "12. "]) + line }
            line = random.pick(["", " ", "\t", "   "]) + line + random.pick(["", " ", "\t"])
            lines.append(line)
            if let whole, !expected.contains(whole) { expected.append(whole) }
            if random.chance(0.15) { lines.append(line) }
        }
        response = lines.joined(separator: random.pick(["\n", "\r\n", "\n\n"]))
        self.expected = expected
    }

    var testDescription: String { "seed \(seed)" }

    /// The line the person typed: words apart, sometimes far apart, sometimes a list item, never blank.
    private static func typed(_ random: inout Seeded) -> String {
        let count =
            random.chance(0.05)
            ? Int.random(in: 30...60, using: &random) : Int.random(in: 1...6, using: &random)
        var text = (0..<count).map { _ in random.pick(words) }.joined(
            separator: random.pick([" ", " ", "  "]))
        if random.chance(0.15) { text = random.pick(["1. ", "- ", "12. ", "* "]) + text }
        if random.chance(0.2) { text += " " }
        return text
    }

    /// The typed text as a model repeats it: case changed, marks dropped or added, inner spaces rewritten, the end intact.
    private static func echo(of typed: String, _ random: inout Seeded) -> String {
        var echo = ""
        var tail = Substring(typed)
        while let last = tail.last, last == " " { tail.removeLast() }
        let trailing = typed.dropFirst(tail.count)
        var index = tail.startIndex
        while index < tail.endIndex {
            let character = tail[index]
            if marks.contains(String(character)) {
                if random.chance(0.5) { echo.append(character) }
            } else if character == " " {
                var run = tail[index...].prefix { $0 == " " }
                index = run.endIndex
                if random.chance(0.6) { run = Substring(random.pick([" ", "  ", "\t", "   "])) }
                echo += run
                continue
            } else if character.isLetter, random.chance(0.3) {
                echo += random.chance(0.5) ? String(character).uppercased() : String(character).lowercased()
            } else {
                echo.append(character)
            }
            if index < tail.index(before: tail.endIndex), random.chance(0.05) { echo += random.pick(marks) }
            index = tail.index(after: index)
        }
        return echo + String(trailing)
    }

    /// What the model adds past the line: the rest of it, a paragraph, a loop, nothing, or marks alone.
    private static func continuation(_ random: inout Seeded) -> String {
        switch Int.random(in: 0..<10, using: &random) {
        case 0: return random.pick(["", " ", "  ", "\t"])
        case 1: return random.pick(marks + [" ™", "\u{200E} ", "™®"])
        case 2: return String(repeating: " word", count: Int.random(in: 33...60, using: &random))
        case 3: return String(repeating: " - sr", count: Int.random(in: 3...12, using: &random))
        case 4: return " " + random.pick(MLXCandidateScorer.promptMarkers) + " please"
        default:
            let count = Int.random(in: 1...5, using: &random)
            return random.pick(["", " ", ", "])
                + (0..<count).map { _ in random.pick(words) }.joined(separator: " ")
        }
    }

    /// Whether the continuation is something to offer: it says something, is not a loop or a paragraph, and quotes no heading.
    private static func isUsable(_ continuation: String, on line: String) -> Bool {
        continuation.contains { !$0.isWhitespace && !MLXCandidateScorer.ignoredMarks.contains($0) }
            && !MLXCandidateScorer.isDegenerate(continuation)
            && !MLXCandidateScorer.promptMarkers.contains(where: line.lowercased().contains)
    }
}

private let replies = (0..<500).map(ParseCase.init)

/// Whether the line, compared loosely, opens with the typed text or is one slip from doing so: a swap, an extra or a changed character.
private func opensWithinOneSlip(_ line: String, of typed: String) -> Bool {
    let loose = Array(MLXCandidateScorer.comparable(line))
    let wanted = Array(MLXCandidateScorer.comparable(typed))
    guard loose.count >= wanted.count else { return false }
    let head = Array(loose.prefix(wanted.count))
    if head == wanted || zip(head, wanted).filter({ $0 != $1 }).count == 1 { return true }
    for at in 0..<max(wanted.count - 1, 0) {
        var swapped = head
        swapped.swapAt(at, at + 1)
        if swapped == wanted { return true }
    }
    guard loose.count > wanted.count else { return false }
    let longer = Array(loose.prefix(wanted.count + 1))
    return (0...wanted.count).contains { at in
        var cut = longer
        cut.remove(at: at)
        return cut == wanted
    }
}

@Suite("Parsing the model's reply, over generated replies")
struct CompletionParsingPropertyTests {
    @Test(
        "Every usable line comes out rebuilt on the typed text, in order, once, and nothing else does.",
        arguments: replies)
    func parsingMatchesTheOracle(reply: ParseCase) {
        #expect(MLXCandidateScorer.parse(reply.response, typed: reply.typed) == reply.expected)
    }

    @Test(
        "Whatever comes out begins with the typed text, adds something to it, and is neither a heading nor a ramble.",
        arguments: replies)
    func resultsKeepTheirShape(reply: ParseCase) {
        let results = MLXCandidateScorer.parse(reply.response, typed: reply.typed)
        #expect(Set(results).count == results.count)
        for result in results {
            #expect(result.hasPrefix(reply.typed))
            #expect(result != reply.typed)
            let continuation = String(result.dropFirst(reply.typed.count))
            let saysSomething = continuation.contains { !$0.isWhitespace }
            #expect(saysSomething)
            #expect(!MLXCandidateScorer.isDegenerate(continuation))
            let quotesAHeading = MLXCandidateScorer.promptMarkers.contains {
                result.lowercased().contains($0)
            }
            #expect(!quotesAHeading)
        }
    }

    @Test(
        "A line more than one slip from opening with the typed text, compared loosely, yields nothing.",
        arguments: 0..<300
    )
    func unrelatedLinesYieldNothing(seed: Int) {
        var random = Seeded(seed: seed)
        let typed = (0..<Int.random(in: 1...4, using: &random)).map { _ in random.pick(words) }.joined(
            separator: " ")
        let line = (0..<Int.random(in: 1...8, using: &random)).map { _ in random.pick(words) }.joined(
            separator: " ")
        guard !opensWithinOneSlip(line, of: typed) else { return }
        #expect(MLXCandidateScorer.parse(line, typed: typed).isEmpty)
        #expect(MLXCandidateScorer.continuation(of: line, past: typed) == nil)
    }

    @Test(
        "Comparing lowercases, drops the marks, folds whitespace runs, and settles after one pass.",
        arguments: 0..<300)
    func comparableIsANormalForm(seed: Int) {
        var random = Seeded(seed: seed)
        var text = ""
        for _ in 0..<Int.random(in: 0...12, using: &random) {
            text += random.pick(words + marks + [" ", "  ", "\t", "\n"])
        }
        let comparable = MLXCandidateScorer.comparable(text)
        #expect(MLXCandidateScorer.comparable(comparable) == comparable)
        #expect(comparable == comparable.lowercased())
        let marked = comparable.contains { MLXCandidateScorer.ignoredMarks.contains($0) }
        let oddSpaced = comparable.contains { $0.isWhitespace && $0 != " " }
        #expect(!marked && !oddSpaced)
        #expect(!comparable.contains("  "))
        #expect(comparable.count <= text.count)
    }

    @Test(
        "A paragraph or a loop is degenerate; a few words, or many different ones, are not.",
        arguments: 0..<200)
    func degeneracyHasTwoShapes(seed: Int) {
        var random = Seeded(seed: seed)
        let few = (0..<Int.random(in: 1...5, using: &random)).map { _ in random.pick(words) }.joined(
            separator: " ")
        #expect(!MLXCandidateScorer.isDegenerate(few))
        let distinct = Array(Set(words)).sorted().shuffled(using: &random).prefix(
            Int.random(in: 6...12, using: &random))
        let varied = distinct.joined(separator: " ")
        #expect(
            MLXCandidateScorer.isDegenerate(varied)
                == (varied.count > MLXCandidateScorer.maximumContinuationLength))
        let word = random.pick(words)
        let loop = Array(repeating: word, count: Int.random(in: 6...20, using: &random)).joined(
            separator: " ")
        #expect(MLXCandidateScorer.isDegenerate(loop))
        let long = String(repeating: "ab ", count: MLXCandidateScorer.maximumContinuationLength)
        #expect(MLXCandidateScorer.isDegenerate(long))
    }

    @Test(
        "Unmarking strips one bullet, one numbering or a fence, and leaves a plain line alone.",
        arguments: 0..<200)
    func unmarkingStripsOneMarker(seed: Int) {
        var random = Seeded(seed: seed)
        let plain = (0..<Int.random(in: 1...5, using: &random)).map { _ in random.pick(words) }.joined(
            separator: " ")
        guard !plain.hasPrefix("-"), !plain.hasPrefix("*"), plain.first?.isNumber != true else { return }
        #expect(MLXCandidateScorer.unmarked(plain) == plain)
        #expect(MLXCandidateScorer.unmarked(random.pick(["- ", "* ", "• "]) + plain) == plain)
        #expect(MLXCandidateScorer.unmarked("\(Int.random(in: 1...99, using: &random)). " + plain) == plain)
        #expect(MLXCandidateScorer.unmarked("```" + plain).isEmpty)
    }
}
