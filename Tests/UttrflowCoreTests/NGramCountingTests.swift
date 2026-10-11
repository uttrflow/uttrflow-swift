// Tests for building a smoothed back-off model from counted sentences, as the user model is built on the device.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("A model counted from sentences is a proper distribution after every history")
struct NGramCountingTests {
    private static let sentences = [
        ["the", "cache", "hit"], ["the", "cache", "missed"], ["the", "cash", "register"],
        ["a", "cache", "hit"], ["the", "cache", "hit"],
    ]
    private static let vocabulary = ["<unk>", "the", "cache", "hit", "missed", "cash", "register", "a"]

    private func total(_ model: NGramModel, after history: [String]) -> Double {
        Self.vocabulary.reduce(0) { $0 + pow(10, Double(model.log10Probability(of: $1, after: history))) }
    }

    @Test(
        "probabilities after a seen, a partly seen and an unseen history each sum to 1",
        arguments: [[], ["the"], ["the", "cache"], ["a", "cash"], ["zebra"], ["zebra", "cache"]])
    func sumsToOne(history: [String]) {
        let model = NGramModel.counted(Self.sentences)
        #expect(abs(total(model, after: history) - 1) < 1e-4)
    }

    @Test("a continuation seen after the history outscores one never seen there")
    func seenContinuationWins() {
        let model = NGramModel.counted(Self.sentences)
        #expect(model.order == 3)
        #expect(
            model.log10Probability(of: "cache", after: ["the"])
                > model.log10Probability(of: "cash", after: ["the"]))
        #expect(
            model.log10Probability(of: "hit", after: ["the", "cache"])
                > model.log10Probability(of: "register", after: ["the", "cache"]))
    }

    @Test("a word never counted scores as unknown, above the floor for a model without one")
    func unseenWordScores() {
        let model = NGramModel.counted(Self.sentences)
        let unseen = model.log10Probability(of: "zebra", after: [])
        #expect(unseen == model.log10Probability(of: "<unk>", after: []))
        #expect(unseen > NGramModel.unseenLog10Probability)
    }

    @Test("the discount follows the count-of-counts, and is one half without both")
    func discountFromCounts() {
        #expect(NGramModel.discount([[1]: 1, [2]: 1, [3]: 2]) == 0.5)
        #expect(NGramModel.discount([[1]: 1, [2]: 1, [3]: 1]) == 0.5)
        #expect(abs(NGramModel.discount([[1]: 1, [2]: 1, [3]: 1, [4]: 2]) - 0.6) < 1e-9)
    }
}
