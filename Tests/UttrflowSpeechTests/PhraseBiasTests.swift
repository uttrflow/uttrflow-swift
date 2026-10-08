// Tests the decode-time nudge that helps a begun dictionary word finish.
import CoreML
import Testing

@testable import UttrflowSpeech

/// A tokeniser with one id per character, so a word's path is its spelling.
private struct LetterTokenizer: PromptTokenizer {
    let firstSpecialToken = 1_000

    func encode(text: String) -> [Int] {
        text.unicodeScalars.map { Int($0.value) }
    }
}

private func ids(_ text: String) -> [Int] {
    LetterTokenizer().encode(text: text)
}

/// Flat scores over the letter ids, with `top` given `topScore`.
private func scores(top: Int, topScore: Float) -> [Float] {
    var scores = [Float](repeating: 0, count: 128)
    scores[top] = topScore
    return scores
}

@Suite("PhraseBias")
struct PhraseBiasTests {
    private let bias = PhraseBias(words: ["zo", "kal"], using: LetterTokenizer(), strength: 2)

    @Test("a word is never started by the bias, only continued")
    func neverStarts() {
        #expect(bias.continuations(after: ids("the")).isEmpty)
        #expect(bias.continuations(after: []).isEmpty)
    }

    @Test("a begun word gets its next token")
    func continuesABegunWord() {
        #expect(bias.continuations(after: ids("the z")) == [Int(UnicodeScalar("o").value)])
        #expect(bias.continuations(after: ids("the ka")) == [Int(UnicodeScalar("l").value)])
    }

    @Test("a one-token word has nothing to continue")
    func singleTokenWordsAreDropped() {
        let short = PhraseBias(words: [""], using: LetterTokenizer(), strength: 2)
        #expect(short.phrases.isEmpty)
        #expect(!short.isActive)
    }

    @Test("the strength is capped and zero turns it off")
    func strengthIsBounded() {
        #expect(
            PhraseBias(words: ["zo"], using: LetterTokenizer(), strength: 99).strength
                == PhraseBias.maximumStrength)
        #expect(!PhraseBias(words: ["zo"], using: LetterTokenizer(), strength: 0).isActive)
        #expect(!PhraseBias(words: ["zo"], using: LetterTokenizer(), strength: -1).isActive)
    }

    @Test("an uncertain step is nudged towards the word")
    func raisesAnUncertainStep() {
        let raised = bias.biased(scores(top: 5, topScore: 1), continuing: [7])
        #expect(raised[7] == 2)
        #expect(raised[5] == 1)
    }

    @Test("a confidently heard token is never outvoted")
    func protectsAConfidentToken() {
        let sure = scores(top: 5, topScore: 20)
        #expect(bias.biased(sure, continuing: [7]) == sure)
    }

    @Test("a token outside the scores is ignored")
    func ignoresOutOfRangeTokens() {
        let flat = scores(top: 5, topScore: 1)
        #expect(bias.biased(flat, continuing: [500]) == flat)
    }

    @Test("the filter raises the continuation in the logits it is handed")
    func filterRaisesLogits() throws {
        let filter = PhraseBiasFilter(bias: bias, sampleBegin: 2, firstSpecialToken: 1_000)
        for type in [MLMultiArrayDataType.float32, .float16] {
            let logits = try MLMultiArray(shape: [1, 1, 128], dataType: type)
            for index in 0..<128 { logits[index] = 0 }
            let next = Int(UnicodeScalar("o").value)
            // Two forced tokens, then a timestamp the match skips, then " z".
            let out = filter.filterLogits(logits, withTokens: [1, 2, 1_500] + ids(" z"))
            #expect(out[next].floatValue == 2)
            #expect(out[0].floatValue == 0)
        }
    }

    @Test("the filter leaves the prefill and unbegun words alone")
    func filterIgnoresPrefill() throws {
        let filter = PhraseBiasFilter(bias: bias, sampleBegin: 5, firstSpecialToken: 1_000)
        let logits = try MLMultiArray(shape: [1, 1, 128], dataType: .float32)
        for index in 0..<128 { logits[index] = 0 }
        _ = filter.filterLogits(logits, withTokens: ids(" z"))
        _ = filter.filterLogits(logits, withTokens: [1, 2, 3, 4, 5] + ids(" q"))
        #expect((0..<128).allSatisfy { logits[$0].floatValue == 0 })
    }

    @Test("the unbiased scores are recovered exactly, whether or not the bias fired")
    func unbiasedInvertsBiased() {
        let uncertain = scores(top: 5, topScore: 1)
        #expect(bias.unbiased(bias.biased(uncertain, continuing: [7]), continuing: [7]) == uncertain)
        let sure = scores(top: 5, topScore: 20)
        #expect(bias.unbiased(bias.biased(sure, continuing: [7]), continuing: [7]) == sure)
    }
}
