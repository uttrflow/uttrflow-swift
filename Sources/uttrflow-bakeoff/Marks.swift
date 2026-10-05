import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowEval
import UttrflowLocalModel

/// Scores who should place commas and stops: each mark on its own, aligned by word match. See `Docs/punctuation-owner.md`.
struct Marks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "marks",
        abstract: "Score commas, stops and question marks per candidate on the prose cases of the corpus."
    )

    @Flag(name: .long, help: "Also run the local MLX model, which loads several gigabytes.")
    var local = false

    @Flag(name: .long, help: "Print every case where a candidate's commas differ from the reference.")
    var verbose = false

    @Option(
        name: .long,
        help:
            "Print the local model's raw reply for this many cases, in one block and as chat turns, then stop."
    )
    var raw = 0

    /// Destinations whose text is prose, where a comma is a choice rather than syntax.
    static let prose: Set<Destination> = [.document, .email, .messaging, .plain]

    func run() async throws {
        let cases = EvaluationCorpus.all.filter { Self.prose.contains($0.destination) }
        print(
            "Marks — \(cases.count) prose cases of \(EvaluationCorpus.all.count), prompt \(PromptBuilder.version)"
        )

        if raw > 0 {
            try await showRaw(cases.prefix(raw))
            return
        }

        var candidates: [(String, (EvaluationCase) async throws -> String?)] = []
        candidates.append(("heard", { $0.spoken }))
        let rules = RuleBasedTransformer()
        candidates.append(("rules", { try await rules.transform($0.transformationRequest()).text }))
        var apple = EngineConfiguration.default
        apple.transformerPreference = [.foundationModels]
        let appleRouter = TextTransformers.router(configuration: apple)
        let appleEngine = TextTransformers.all().first { $0.kind == .foundationModels }
        candidates.append(
            (
                "apple",
                { testCase in
                    let request = testCase.transformationRequest()
                    if let appleEngine, await appleEngine.availability(for: request).isAvailable == false {
                        return nil
                    }
                    return try await appleRouter.transform(request).text
                }
            ))
        if local {
            let cleanup = MLXCandidateScorer(model: .gemma3)
            try await cleanup.prepare()
            let transformer = TextTransformers.local(cleanup)
            let router = PassThroughRouter(engine: transformer)
            candidates.append(("local", { try await router.text(for: $0.transformationRequest()) }))
        }

        var tallies: [MarkTally] = []
        let clock = ContinuousClock()
        for (name, produce) in candidates {
            var tally = MarkTally(name: name)
            for testCase in cases {
                FileHandle.standardError.write(Data("\(name) \(testCase.id)\n".utf8))
                let start = clock.now
                let produced: String?
                do {
                    produced = try await produce(testCase)
                    if produced == nil { tally.declines["unavailable", default: 0] += 1 }
                } catch {
                    produced = nil
                    tally.declines[Self.reason(error), default: 0] += 1
                    FileHandle.standardError.write(Data("  declined \(testCase.id): \(error)\n".utf8))
                }
                tally.seconds.append(Self.seconds(start.duration(to: clock.now)))
                guard let produced else {
                    tally.perCase.append(nil)
                    continue
                }
                let counts = MarkCounts(produced: produced, wanted: testCase.expected, heard: testCase.spoken)
                tally.perCase.append(counts)
                if verbose, counts.comma.falsePositive + counts.comma.falseNegative > 0 {
                    print("  \(name) \(testCase.id): \(produced)  ‖  \(testCase.expected)")
                }
            }
            tallies.append(tally)
        }
        print(MarkTally.table(tallies))
        print("\nDeclines by reason:")
        for tally in tallies where !tally.declines.isEmpty {
            for (reason, count) in tally.declines.sorted(by: { $0.value > $1.value }) {
                print("  " + tally.name.padded(to: 15) + "\(count)".padded(to: 6) + reason)
            }
        }
        if let rulesTally = tallies.first(where: { $0.name == "rules" }) {
            print("\nComma F1 difference against rules, paired over cases, 95% bootstrap interval:")
            for tally in tallies where tally.name != "rules" {
                print("  " + tally.name.padded(to: 15) + tally.commaDifference(against: rulesTally))
            }
        }
    }

    /// The model's untouched reply to the shipping prompt, first as one instruction block, then with the examples as turns.
    private func showRaw(_ cases: ArraySlice<EvaluationCase>) async throws {
        let model = MLXCandidateScorer(model: .gemma3)
        try await model.prepare()
        for testCase in cases {
            let request = testCase.transformationRequest()
            let conversation = PromptBuilder.standard.conversation(for: request.situation.destination)
            let question = PromptBuilder.standard.userPrompt(for: request)
            let block = try await model.rewrite(
                question, instructions: conversation.instructions, kind: .localModel)
            let turns = try await model.rewrite(question, prompt: conversation, kind: .localModel)
            print("\(testCase.id)\n  spoken: \(testCase.spoken)\n  block:  \(block)\n  turns:  \(turns)")
        }
    }

    /// The class of a decline, so a guard refusal is told apart from a load error or a timeout.
    static func reason(_ error: any Error) -> String {
        switch error as? TransformationError {
        case .outputRejected(_, let kind): "guard: \(kind)"
        case .transformFailed(_, let failure): "failed: \(failure)"
        case .noCapableTransformer: "no capable transformer"
        case .cancelled: "cancelled"
        case nil: "error: \(type(of: error))"
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// The local model alone, with no rules floor behind it, so a refusal counts as a decline.
private struct PassThroughRouter: Sendable {
    let engine: GenerativeTextTransformer

    func text(for request: TransformationRequest) async throws -> String? {
        guard await engine.availability(for: request).isAvailable else { return nil }
        return try await engine.transform(request).text
    }
}

/// True and false placements of one mark.
struct MarkCount: Sendable {
    var truePositive = 0
    var falsePositive = 0
    var falseNegative = 0

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            truePositive: lhs.truePositive + rhs.truePositive,
            falsePositive: lhs.falsePositive + rhs.falsePositive,
            falseNegative: lhs.falseNegative + rhs.falseNegative)
    }

    var f1: Double {
        let denominator = 2 * truePositive + falsePositive + falseNegative
        return denominator == 0 ? 1 : Double(2 * truePositive) / Double(denominator)
    }
}

/// Per-mark counts for one case, over the words the output and the reference share.
struct MarkCounts: Sendable {
    enum Mark: CaseIterable { case comma, stop, question }

    var comma = MarkCount()
    var stop = MarkCount()
    var question = MarkCount()
    /// Words in the output that were not heard plus heard words the output lost.
    var wordsChanged = 0

    init(produced: String, wanted: String, heard: String) {
        let out = Self.marked(produced)
        let ref = Self.marked(wanted)
        for (i, j) in Self.alignment(out.map(\.word), ref.map(\.word)) {
            add(out[i].mark, ref[j].mark)
        }
        let heardWords = Self.marked(heard).map(\.word)
        let kept = Self.alignment(out.map(\.word), heardWords).count
        wordsChanged = (out.count - kept) + (heardWords.count - kept)
    }

    init() {}

    private mutating func add(_ produced: Mark?, _ wanted: Mark?) {
        guard produced != wanted else {
            if let produced { self[produced].truePositive += 1 }
            return
        }
        if let produced { self[produced].falsePositive += 1 }
        if let wanted { self[wanted].falseNegative += 1 }
    }

    subscript(mark: Mark) -> MarkCount {
        get {
            switch mark {
            case .comma: comma
            case .stop: stop
            case .question: question
            }
        }
        set {
            switch mark {
            case .comma: comma = newValue
            case .stop: stop = newValue
            case .question: question = newValue
            }
        }
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        var sum = Self()
        sum.comma = lhs.comma + rhs.comma
        sum.stop = lhs.stop + rhs.stop
        sum.question = lhs.question + rhs.question
        sum.wordsChanged = lhs.wordsChanged + rhs.wordsChanged
        return sum
    }

    /// Lower-cased words, each with the mark that follows it; "!" counts as a stop.
    static func marked(_ text: String) -> [(word: String, mark: Mark?)] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let word = token.lowercased().filter { $0.isLetter || $0.isNumber }
            guard !word.isEmpty else { return nil }
            let tail = token.reversed().prefix { !($0.isLetter || $0.isNumber) }
            let mark: Mark? =
                tail.contains("?")
                ? .question
                : tail.contains(where: { $0 == "." || $0 == "!" })
                    ? .stop
                    : tail.contains(",") ? .comma : nil
            return (word, mark)
        }
    }

    /// Index pairs of a longest common subsequence, so marks are compared only on words both sides hold.
    static func alignment(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}

/// One candidate's results over every case, `nil` where it declined.
struct MarkTally: Sendable {
    let name: String
    var perCase: [MarkCounts?] = []
    var seconds: [Double] = []
    /// Declined cases by reason: the guard's refusal kind, the failure class, or `unavailable`.
    var declines: [String: Int] = [:]

    var total: MarkCounts { perCase.compactMap(\.self).reduce(MarkCounts(), +) }

    static func table(_ tallies: [MarkTally]) -> String {
        let header =
            "candidate".padded(to: 15) + "comma F1".padded(to: 10) + "P/R".padded(to: 12)
            + "stop F1".padded(to: 9)
            + "question F1".padded(to: 13) + "words changed".padded(to: 15) + "p50".padded(to: 8)
            + "p95".padded(to: 8) + "declined"
        var lines = ["", header, String(repeating: "─", count: header.count)]
        for tally in tallies {
            let total = tally.total
            let comma = total.comma
            let precision =
                Double(comma.truePositive) / Double(max(1, comma.truePositive + comma.falsePositive))
            let recall = Double(comma.truePositive) / Double(max(1, comma.truePositive + comma.falseNegative))
            let sorted = tally.seconds.sorted()
            let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 95 / 100)]
            lines.append(
                tally.name.padded(to: 15) + fixed(comma.f1).padded(to: 10)
                    + "\(fixed(precision))/\(fixed(recall))".padded(to: 12)
                    + fixed(total.stop.f1).padded(to: 9)
                    + fixed(total.question.f1).padded(to: 13) + "\(total.wordsChanged)".padded(to: 15)
                    + String(format: "%.2fs", p50).padded(to: 8) + String(format: "%.2fs", p95).padded(to: 8)
                    + "\(tally.perCase.filter { $0 == nil }.count)")
        }
        return lines.joined(separator: "\n")
    }

    /// Comma F1 of this tally minus the other's, over cases both answered, with a seeded 2000-draw bootstrap.
    func commaDifference(against other: MarkTally) -> String {
        let paired = zip(perCase, other.perCase).compactMap { a, b in
            a.flatMap { a in b.map { (a.comma, $0.comma) } }
        }
        guard !paired.isEmpty else { return "no shared cases" }
        func difference(_ sample: [(MarkCount, MarkCount)]) -> Double {
            sample.map(\.0).reduce(MarkCount(), +).f1 - sample.map(\.1).reduce(MarkCount(), +).f1
        }
        var generator = SplitMix(seed: 3857)
        var draws: [Double] = []
        for _ in 0..<2000 {
            draws.append(
                difference(
                    (0..<paired.count).map { _ in paired[Int(generator.next() % UInt64(paired.count))] }))
        }
        draws.sort()
        return
            "\(signed(difference(paired))) [\(signed(draws[50])), \(signed(draws[1949]))] over \(paired.count) cases"
    }
}

/// A seeded generator so the interval is the same on every run.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func fixed(_ value: Double) -> String { String(format: "%.2f", value) }
private func signed(_ value: Double) -> String { String(format: "%+.2f", value) }
