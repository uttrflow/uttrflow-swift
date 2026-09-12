// Holds the decoding rules a prompted decode is given, since a prompt is what silences WhisperKit's own.
import CoreML
import Testing
import WhisperKit

@testable import UttrflowSpeech

/// The prefill a prompted decode forces, and the timestamp rules measured from it.
@Suite("The decoder prefill")
struct DecoderPrefillTests {
    /// A vocabulary shaped like Whisper's — words below the instructions, timestamps above them.
    static let specialTokens = SpecialTokens(
        endToken: 50,
        englishToken: 52,
        noSpeechToken: 56,
        noTimestampsToken: 57,
        specialTokenBegin: 50,
        startOfPreviousToken: 55,
        startOfTranscriptToken: 51,
        timeTokenBegin: 58,
        transcribeToken: 53,
        translateToken: 54,
        whitespaceToken: 1
    )

    /// Ids past the last timestamp, which is where the fixture's vocabulary ends.
    static let vocabularySize = 64

    /// Three words of a personal dictionary, none of which instructs the decoder.
    static let prompt = [10, 11, 12]

    /// What WhisperKit force-feeds for that prompt: start-of-previous, the words, then the four opening tokens.
    static let prefilledTokens = [55, 10, 11, 12, 51, 52, 53, 58]

    // MARK: What is forced before the transcript

    @Test("counts the start-of-previous token, the prompt and the four opening tokens")
    func countsAPromptedMultilingualPrefill() {
        let prefill = DecoderPrefill(
            promptTokens: Self.prompt, specialTokenBegin: 50, isMultilingual: true)

        #expect(prefill.count == Self.prefilledTokens.count)
    }

    @Test("drops the language and the task for a model that knows only English")
    func countsAnEnglishOnlyPrefill() {
        let prefill = DecoderPrefill(
            promptTokens: Self.prompt, specialTokenBegin: 50, isMultilingual: false)

        #expect(prefill.count == 6)
    }

    @Test("counts no start-of-previous token when there is no prompt to carry it")
    func countsAnUnpromptedPrefill() {
        #expect(
            DecoderPrefill(promptTokens: nil, specialTokenBegin: 50, isMultilingual: true).count
                == 4)
    }

    /// WhisperKit drops a prompt nothing survives rather than forcing a bare start-of-previous token.
    @Test("counts a prompt of nothing but instructions as no prompt at all")
    func countsAPromptThatIsAllSpecialTokens() {
        let prefill = DecoderPrefill(
            promptTokens: [50, 51, 57], specialTokenBegin: 50, isMultilingual: true)

        #expect(prefill.count == 4)
    }

    /// The decoder keeps the last 111 tokens of a longer prompt, so the prefill stops growing there.
    @Test("counts only the tokens a prompt past the ceiling has left after trimming")
    func countsATrimmedPrompt() {
        let prefill = DecoderPrefill(
            promptTokens: Array(repeating: 10, count: VocabularyPrompt.maximumTokens + 40),
            specialTokenBegin: 50,
            isMultilingual: true
        )

        #expect(prefill.count == VocabularyPrompt.maximumTokens + 5)
    }

    // MARK: The rules a prompt would otherwise cost the decode

    /// WhisperKit's own copy searches the first three tokens for the task token and a prompt puts it past them.
    @Test("forbids the no-timestamps token at the first sampled token of a prompted decode")
    func timestampRulesAreLiveBehindAPrompt() throws {
        let logits = try Logits(dominantToken: 5)

        _ = Self.filters().filtered(logits.array, tokens: Self.prefilledTokens)

        #expect(logits[Self.specialTokens.noTimestampsToken] == -FloatType.infinity)
    }

    /// The step where the prefill ends is the first real prediction, and an end token there is the decoder's own.
    @Test("leaves the end token alone at the first sampled token, where an end is a prediction")
    func theEndTokenSurvivesTheFirstPrediction() throws {
        let logits = try Logits(dominantToken: 5)

        _ = Self.filters().filtered(logits.array, tokens: Self.prefilledTokens)

        #expect(logits[Self.specialTokens.endToken] > -FloatType.infinity)
    }

    /// Timestamps come in pairs, which is the rule that stops a window looping until the thresholds catch it.
    @Test("forbids a second timestamp directly after the first one a prompted decode sampled")
    func timestampsArePairedBehindAPrompt() throws {
        let logits = try Logits(dominantToken: 5)

        _ = Self.filters().filtered(
            logits.array, tokens: Self.prefilledTokens + [Self.specialTokens.timeTokenBegin + 2])

        #expect(logits[Self.specialTokens.timeTokenBegin + 3] == -FloatType.infinity)
        #expect(logits[5] > -FloatType.infinity)
    }

    /// The rules a prompted multilingual decode is given, as `WhisperKitBackend` installs them.
    private static func filters() -> [any LogitsFiltering] {
        DecoderPrefill(promptTokens: prompt, specialTokenBegin: 50, isMultilingual: true)
            .logitsFilters(specialTokens: specialTokens)
    }
}

extension [any LogitsFiltering] {
    /// Runs every filter over `logits`, the way the decode loop does.
    fileprivate func filtered(_ logits: MLMultiArray, tokens: [Int]) -> MLMultiArray {
        reduce(logits) { $1.filterLogits($0, withTokens: tokens) }
    }
}

/// One step's logits, with a single token the decoder is sure of so the rules never see a tie.
private struct Logits {
    let array: MLMultiArray

    init(dominantToken: Int) throws {
        array = try MLMultiArray(
            shape: [1, 1, NSNumber(value: DecoderPrefillTests.vocabularySize)], dataType: .float16)
        array.withUnsafeMutableBufferPointer(ofType: FloatType.self) { buffer, _ in
            for index in 0..<DecoderPrefillTests.vocabularySize { buffer[index] = 0 }
            buffer[dominantToken] = 20
        }
    }

    subscript(token: Int) -> FloatType {
        array.withUnsafeBufferPointer(ofType: FloatType.self) { buffer in buffer[token] }
    }
}
