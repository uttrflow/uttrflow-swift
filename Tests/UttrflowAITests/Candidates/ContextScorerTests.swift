// Tests for interpolating n-gram models and for the context verdict on a span's candidates, with the speed and memory probe.

import Darwin
import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

@Suite("The context scorer prefers a candidate only when the surrounding words separate it clearly")
struct ContextScorerTests {
    private static let technical = """
        \\data\\
        ngram 1=5
        ngram 2=3

        \\1-grams:
        -2.0 <unk>
        -1.0 the -0.5
        -1.5 cache -0.5
        -1.5 cash -0.5
        -1.2 hit

        \\2-grams:
        -0.3 the cache
        -2.5 the cash
        -0.2 cache hit

        \\end\\
        """

    private func scorer(margin: Float = ContextScorer.defaultMargin) throws -> ContextScorer {
        let model = try ARPAReader.model(from: Self.technical)
        return ContextScorer(
            model: InterpolatedLanguageModel([.init(model: model, weight: 1)]), margin: margin)
    }

    @Test("A candidate that fits both neighbours by the margin is preferred")
    func prefersFittingCandidate() throws {
        let verdict = try scorer().verdict(on: [["cash"], ["cache"]], between: ["the"], and: ["hit"])
        #expect(verdict == .prefers(1))
    }

    @Test("A lead under the margin leaves the choice to other evidence")
    func undecidedUnderMargin() throws {
        let verdict = try scorer(margin: 10).verdict(
            on: [["cash"], ["cache"]], between: ["the"], and: ["hit"])
        #expect(verdict == .undecided)
        #expect(try scorer().verdict(on: [["cache"]], between: ["the"], and: []) == .undecided)
    }

    @Test("Interpolation mixes probabilities by the scaled weights")
    func interpolates() throws {
        let model = try ARPAReader.model(from: Self.technical)
        let flat = try ARPAReader.model(from: "\\data\\\nngram 1=1\n\\1-grams:\n0 cash\n\\end\\\n")
        let mixed = InterpolatedLanguageModel([
            .init(model: model, weight: 3), .init(model: flat, weight: 1), .init(model: flat, weight: 0),
        ])
        let expected = log10f(0.75 * powf(10, -2.5) + 0.25 * 1)
        #expect(abs(mixed.log10Probability(of: "cash", after: ["the"]) - expected) < 1e-5)
    }

    @Test("Behind the span seam, the reading the neighbours prefer is offered first")
    func spanScorerLiftsFittingReading() async throws {
        let source = ScriptedCandidates(["cashe": ["Cash", "cache"]])
        let doubtful = DoubtfulWords(sources: [source], scorer: ContextSpanScorer(context: try scorer()))
        let spans = await doubtful.spans(in: .heard("the ?cashe hit"), for: .unknown)
        #expect(spans.first?.candidates.map(\.spelling) == ["cache", "Cash"])
    }

    @Test("Behind the span seam, an undecided context keeps the sources' order")
    func spanScorerUndecidedKeepsOrder() async throws {
        let source = ScriptedCandidates(["cashe": ["Cash", "cache"]])
        let undecided = DoubtfulWords(
            sources: [source], scorer: ContextSpanScorer(context: try scorer(margin: 10)))
        let spans = await undecided.spans(in: .heard("the ?cashe hit"), for: .unknown)
        #expect(spans.first?.candidates.map(\.spelling) == ["Cash", "cache"])
        let set = HypothesisSet(heard: "cashe", confidence: 0.2, answers: [["Cash", "cache"]])
        #expect(ContextSpanScorer(context: try scorer()).cost == .lookup)
        #expect(ContextSpanScorer(context: try scorer()).scores(for: set) == [0, -1])
    }

    @Test("Probe: a counted user model scores ten candidates of a span in under 1 ms")
    func probeCountedModel() throws {
        var generator = SyntheticARPA.Generator(state: 0x2545_F491_4F6C_DD1D)
        let sentences = (0..<20_000).map { _ in (0..<12).map { _ in "w\(generator.word(below: 5_000))" } }
        let clock = ContinuousClock()
        var model: NGramModel?
        let build = clock.measure { model = NGramModel.counted(sentences) }
        let built = try #require(model)
        let scorer = ContextScorer(model: InterpolatedLanguageModel([.init(model: built, weight: 1)]))
        let candidates = (0..<10).map { ["w\($0 * 7)", "w\($0 * 13)"] }
        let rounds = 1_000
        let elapsed = clock.measure {
            for round in 0..<rounds {
                _ = scorer.verdict(
                    on: candidates, between: ["w\(round % 500)", "w\(round % 300)"], and: ["w1", "w2"])
            }
        }
        print("ngram-probe counted nGrams=\(built.nGramCount) build=\(build) perSpan=\(elapsed / rounds)")
        #expect(elapsed / rounds < .milliseconds(1))
    }

    @Test("Probe: a pruned 3-gram of 400,000 n-grams scores ten candidates of a span in under 1 ms")
    func probeSpeedAndMemory() throws {
        let text = SyntheticARPA.text(vocabulary: 20_000, bigrams: 200_000, trigrams: 200_000)
        let before = SyntheticARPA.footprintBytes()
        let clock = ContinuousClock()
        var model: NGramModel?
        let load = clock.measure { model = try? ARPAReader.model(from: text) }
        let loaded = try #require(model)
        let resident = SyntheticARPA.footprintBytes() - before
        let scorer = ContextScorer(
            model: InterpolatedLanguageModel([
                .init(model: loaded, weight: 0.7), .init(model: loaded, weight: 0.3),
            ]))
        let candidates = (0..<10).map { ["w\($0 * 7)", "w\($0 * 13)"] }
        let rounds = 1_000
        let elapsed = clock.measure {
            for round in 0..<rounds {
                _ = scorer.verdict(
                    on: candidates, between: ["w\(round % 500)", "w\(round % 300)"], and: ["w1", "w2"])
            }
        }
        let perSpan = elapsed / rounds
        print(
            "ngram-probe nGrams=\(loaded.nGramCount) text=\(text.utf8.count)B load=\(load) footprint=\(resident)B perSpan=\(perSpan)"
        )
        #expect(perSpan < .milliseconds(1))
    }
}

/// A deterministic random ARPA file of a given size, for measuring the reader and scorer without a real corpus.
enum SyntheticARPA {
    static func text(vocabulary: Int, bigrams: Int, trigrams: Int) -> String {
        var generator = Generator(state: 0x9E37_79B9_7F4A_7C15)
        var lines = [
            "\\data\\", "ngram 1=\(vocabulary)", "ngram 2=\(bigrams)", "ngram 3=\(trigrams)", "",
            "\\1-grams:",
        ]
        lines += (0..<vocabulary).map { "-\(generator.probability()) w\($0) -\(generator.probability())" }
        lines += section(order: 2, count: bigrams, vocabulary: vocabulary, generator: &generator)
        lines += section(order: 3, count: trigrams, vocabulary: vocabulary, generator: &generator)
        return (lines + ["", "\\end\\", ""]).joined(separator: "\n")
    }

    private static func section(
        order: Int, count: Int, vocabulary: Int, generator: inout Generator
    ) -> [String] {
        var seen = Set<[Int]>()
        var lines = ["", "\\\(order)-grams:"]
        while seen.count < count {
            let words = (0..<order).map { _ in generator.word(below: vocabulary) }
            guard seen.insert(words).inserted else { continue }
            let backoff = order < 3 ? " -\(generator.probability())" : ""
            lines.append(
                "-\(generator.probability()) " + words.map { "w\($0)" }.joined(separator: " ") + backoff)
        }
        return lines
    }

    static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }

        mutating func probability() -> String { String(format: "%.4f", Double(next() % 50_000) / 10_000) }

        mutating func word(below vocabulary: Int) -> Int { Int(next() % UInt64(min(vocabulary, 2_000))) }
    }
}
