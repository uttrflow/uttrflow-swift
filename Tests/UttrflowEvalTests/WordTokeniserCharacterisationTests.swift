import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

/// Each tokeniser's words for one awkward string, in the order shape, guard, splice, echo, score, norm.
struct TokenisedCase: Sendable, CustomTestStringConvertible {
    let text: String
    let shape: [String]
    let guarded: [String]
    let splice: [String]
    let echo: [String]
    let score: [String]
    let norm: [String]

    var testDescription: String { text }
}

/// Pins how every word tokeniser cuts the same text today, so replacing them with one seam shows each difference.
@Suite("Word tokeniser characterisation")
struct WordTokeniserCharacterisationTests {
    static let cases: [TokenisedCase] = [
        TokenisedCase(
            text: "don't stop", shape: ["don", "t", "stop"], guarded: ["don't", "stop"],
            splice: ["don't", "stop"],
            echo: ["don", "t", "stop"], score: ["don", "t", "stop"], norm: ["dont", "stop"]),
        TokenisedCase(
            text: "don\u{2019}t stop", shape: ["don", "t", "stop"], guarded: ["don\u{2019}t", "stop"],
            splice: ["don\u{2019}t", "stop"], echo: ["don", "t", "stop"], score: ["don", "t", "stop"],
            norm: ["dont", "stop"]),
        TokenisedCase(
            text: "well-known fact", shape: ["well", "known", "fact"], guarded: ["well", "known", "fact"],
            splice: ["well-known", "fact"], echo: ["well", "known", "fact"],
            score: ["well", "known", "fact"],
            norm: ["well", "known", "fact"]),
        TokenisedCase(
            text: "and/or", shape: ["and", "or"], guarded: ["and", "or"], splice: ["and/or"],
            echo: ["and", "or"],
            score: ["and", "or"], norm: ["and", "or"]),
        TokenisedCase(
            text: "at 5 p.m. today", shape: ["at", "5", "p", "m", "today"],
            guarded: ["at", "5", "p.m", "today"],
            splice: ["at", "5", "p.m.", "today"], echo: ["at", "5", "p", "m", "today"],
            score: ["at", "5", "p", "m", "today"], norm: ["at", "5", "p.m", "today"]),
        TokenisedCase(
            text: "the U.S. team", shape: ["the", "u", "s", "team"], guarded: ["the", "U.S", "team"],
            splice: ["the", "U.S.", "team"], echo: ["the", "U", "S", "team"],
            score: ["the", "u", "s", "team"],
            norm: ["the", "u.s", "team"]),
        TokenisedCase(
            text: "1,000.50 dollars", shape: ["1", "000", "50", "dollars"], guarded: ["1000.50", "dollars"],
            splice: ["1,000.50", "dollars"], echo: ["1", "000", "50", "dollars"],
            score: ["1", "000", "50", "dollars"], norm: ["1", "000.50", "dollars"]),
        TokenisedCase(
            text: "मेरा नाम", shape: ["मेरा", "नाम"], guarded: ["मेरा", "नाम"], splice: ["मेरा", "नाम"],
            echo: ["मेरा", "नाम"], score: ["मेरा", "नाम"], norm: ["मेरा", "नाम"]),
        TokenisedCase(
            text: "  two  spaces ", shape: ["two", "spaces"], guarded: ["two", "spaces"],
            splice: ["two", "spaces"],
            echo: ["two", "spaces"], score: ["two", "spaces"], norm: ["2", "spaces"]),
        TokenisedCase(
            text: "end. Next", shape: ["end", "next"], guarded: ["end", "Next"], splice: ["end.", "Next"],
            echo: ["end", "Next"], score: ["end", "next"], norm: ["end", "next"]),
    ]

    @Test(arguments: cases)
    func everyTokeniserCutsTheTextAsItDoesToday(_ pinned: TokenisedCase) {
        #expect(WordShape.words(pinned.text) == pinned.shape)
        #expect(TextTidy.words(pinned.text) == pinned.shape)
        #expect(MeaningPreservationGuard.grammarTokens(pinned.text).map(\.text) == pinned.guarded)
        #expect(WordCorrection.tokens(pinned.text) == pinned.splice)
        #expect(CaretEchoPass.words(pinned.text) == pinned.echo)
        #expect(Scorer.tokens(pinned.text) == pinned.score)
        #expect(TextNormaliser.standard.words(pinned.text) == pinned.norm)
    }
}
