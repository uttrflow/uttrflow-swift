// Tests for reading an ARPA model and scoring words with back-off.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("An ARPA model reads only when well formed, and scores missing n-grams by backing off")
struct ARPAReaderTests {
    private static let sample = """
        \\data\\
        ngram 1=4
        ngram 2=2
        ngram 3=1

        \\1-grams:
        -1.0 <unk>
        -0.5 the -0.3
        -0.7 cache -0.2
        -1.2 hit

        \\2-grams:
        -0.2 the cache -0.1
        -0.4 cache hit

        \\3-grams:
        -0.05 the cache hit

        \\end\\
        """

    private func failure(_ text: String, limits: ARPALimits = .standard) -> ARPAError? {
        do {
            _ = try ARPAReader.model(from: text, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    @Test("A well-formed file gives its order, words and n-grams")
    func readsCounts() throws {
        let model = try ARPAReader.model(from: Self.sample)
        #expect(model.order == 3)
        #expect(model.vocabularyCount == 4)
        #expect(model.nGramCount == 7)
    }

    @Test("A listed n-gram scores its own probability")
    func listedNGram() throws {
        let model = try ARPAReader.model(from: Self.sample)
        #expect(model.log10Probability(of: "hit", after: ["the", "cache"]) == -0.05)
        #expect(model.log10Probability(of: "cache", after: ["the"]) == -0.2)
    }

    @Test("A missing n-gram adds the history's back-off weight to the shorter n-gram")
    func backsOff() throws {
        let model = try ARPAReader.model(from: Self.sample)
        #expect(abs(model.log10Probability(of: "hit", after: ["the"]) - (-0.3 + -1.2)) < 1e-6)
        #expect(abs(model.log10Probability(of: "the", after: ["cache", "hit"]) - -0.5) < 1e-6)
    }

    @Test("A word outside the vocabulary scores as <unk>, or the floor when the file has none")
    func unknownWord() throws {
        let model = try ARPAReader.model(from: Self.sample)
        #expect(model.log10Probability(of: "zebra", after: []) == -1.0)
        #expect(abs(model.log10Probability(of: "zebra", after: ["the"]) - (-0.3 + -1.0)) < 1e-6)
        let bare = try ARPAReader.model(from: "\\data\\\nngram 1=1\n\\1-grams:\n-0.1 a\n\\end\\\n")
        #expect(bare.log10Probability(of: "zebra", after: []) == NGramModel.unseenLog10Probability)
    }

    @Test("Each malformed file is refused with its reason")
    func refusals() {
        #expect(
            failure(Self.sample, limits: ARPALimits(maxBytes: 10, maxNGrams: 100))
                == .tooLarge(bytes: Self.sample.utf8.count))
        #expect(
            failure(Self.sample, limits: ARPALimits(maxBytes: 4_096, maxNGrams: 5))
                == .tooManyNGrams(count: 6))
        #expect(failure("\\data\\\nngram 4=1\n") == .unsupportedOrder(4))
        #expect(
            failure(Self.sample.replacingOccurrences(of: "-1.2 hit", with: "x hit")) == .malformed(line: 10))
        #expect(
            failure(Self.sample.replacingOccurrences(of: "ngram 2=2", with: "ngram 2=3"))
                == .countMismatch(order: 2, declared: 3, found: 2))
        #expect(
            failure(Self.sample.replacingOccurrences(of: "-1.2 hit", with: "-1.2 cache"))
                == .duplicate(line: 10))
        #expect(failure(Self.sample.replacingOccurrences(of: "\\end\\", with: "")) == .malformed(line: 0))
        #expect(failure("-0.1 a\n") == .malformed(line: 1))
    }
}
