// Tests WordErrorRate against an independent Levenshtein on random pairs.

import Testing

@testable import UttrflowCore

/// Checks the total edit count, not the S/D/I split, against a naive Levenshtein on pairs nobody thought of.
@Suite("Word error rate, against an independent implementation")
struct WordErrorRateDifferentialTests {
    /// Textbook Levenshtein over words, sharing nothing with the implementation under test.
    private func edits(_ reference: [String], _ hypothesis: [String]) -> Int {
        var previous = Array(0...hypothesis.count)
        var current = [Int](repeating: 0, count: hypothesis.count + 1)
        for i in 1...max(reference.count, 1) where !reference.isEmpty {
            current[0] = i
            for j in 0..<hypothesis.count {
                let substitution = previous[j] + (reference[i - 1] == hypothesis[j] ? 0 : 1)
                current[j + 1] = min(substitution, previous[j + 1] + 1, current[j] + 1)
            }
            swap(&previous, &current)
        }
        return reference.isEmpty ? hypothesis.count : previous[hypothesis.count]
    }

    /// A deterministic generator, so a failure names a pair that can be reproduced exactly.
    private func words(seed: inout UInt64, count: Int, from alphabet: [String]) -> [String] {
        (0..<count).map { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return alphabet[Int((seed >> 33) % UInt64(alphabet.count))]
        }
    }

    @Test("agrees with a textbook edit distance over a thousand random pairs")
    func agreesWithTextbookEditDistance() {
        // A small alphabet on purpose: repeated words are what create ambiguous alignments.
        let alphabet = ["the", "cat", "sat", "on", "mat", "a", "quick"]
        var seed: UInt64 = 20_260_823

        for _ in 0..<1_000 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let referenceLength = Int((seed >> 33) % 9)
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let hypothesisLength = Int((seed >> 33) % 9)

            let reference = words(seed: &seed, count: referenceLength, from: alphabet)
            let hypothesis = words(seed: &seed, count: hypothesisLength, from: alphabet)

            let measured = WordErrorRate.measure(reference: reference, hypothesis: hypothesis)
            let total =
                measured.count(of: .substitution) + measured.count(of: .deletion)
                + measured.count(of: .insertion)

            #expect(
                total == edits(reference, hypothesis),
                """
                disagreed on
                  reference:  \(reference)
                  hypothesis: \(hypothesis)
                """)
        }
    }

    /// An empty reference has no denominator; everything else divides by the words the speaker said.
    @Test("the rate is the edit count over the reference length")
    func rateDividesByTheReference() {
        let alphabet = ["one", "two", "three", "four"]
        var seed: UInt64 = 99

        for _ in 0..<200 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let reference = words(seed: &seed, count: Int((seed >> 33) % 7), from: alphabet)
            let hypothesis = words(seed: &seed, count: Int((seed >> 33) % 7), from: alphabet)

            let measured = WordErrorRate.measure(reference: reference, hypothesis: hypothesis)
            guard !reference.isEmpty else {
                #expect(measured.rate == nil, "an empty reference cannot have a rate")
                continue
            }
            let expected = Double(edits(reference, hypothesis)) / Double(reference.count)
            #expect(measured.rate == expected)
        }
    }
}
