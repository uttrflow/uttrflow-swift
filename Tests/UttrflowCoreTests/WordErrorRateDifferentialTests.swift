import Testing

@testable import UttrflowCore

/// Checks the word error rate against a second, deliberately naive implementation.
///
/// The hand-worked examples elsewhere prove the rate is right on the cases somebody
/// thought of. This proves it on cases nobody thought of, which is where an alignment
/// bug actually lives: a wrong tie-break or an off-by-one in the matrix survives every
/// example that happens to have one obvious alignment, and only shows up on a pair where
/// two alignments cost nearly the same.
///
/// The comparison is on the TOTAL number of edits, not the split between substitutions,
/// deletions and insertions. Two minimal alignments of equal cost can disagree about
/// that split — one calls it a substitution, the other a deletion plus an insertion of
/// the same size — and neither is wrong. The total is what the rate divides.
@Suite("Word error rate, against an independent implementation")
struct WordErrorRateDifferentialTests {
    /// Textbook Levenshtein over words, written for obviousness rather than speed: a
    /// full matrix, no banding, no early exit, nothing shared with the implementation
    /// under test.
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

    /// A deterministic generator, so a failure names a pair that can be reproduced
    /// exactly rather than one that has already evaporated.
    private func words(seed: inout UInt64, count: Int, from alphabet: [String]) -> [String] {
        (0..<count).map { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return alphabet[Int((seed >> 33) % UInt64(alphabet.count))]
        }
    }

    @Test("agrees with a textbook edit distance over a thousand random pairs")
    func agreesWithTextbookEditDistance() {
        // A small alphabet on purpose: repeated words are what create the ambiguous
        // alignments a larger vocabulary would almost never produce by chance.
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

    /// The rate itself, not just the alignment: an empty reference has no denominator,
    /// and everything else divides by the number of words the speaker actually said.
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
