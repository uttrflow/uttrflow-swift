// Asserts the upstream facts the prompt is sized from, since prose cannot fail a build.
import Testing
import WhisperKit

@testable import UttrflowSpeech

/// What the product assumes about the recogniser it links, checked against the recogniser it links.
@Suite("The WhisperKit contract")
struct WhisperKitContractTests {
    @Test("the decoder's context window is the 224 tokens every budget here is derived from")
    func contextWindow() {
        #expect(Constants.maxTokenContext == 224)
    }

    /// The one derivation: exceed this and the decoder drops the words we asked it to listen for.
    @Test("the prompt cap the decoder enforces is the number VocabularyPrompt sizes itself to")
    func promptCapIsTheOneWeSizeTo() {
        #expect((Constants.maxTokenContext / 2) - 1 == VocabularyPrompt.maximumTokens)
    }

    /// A clip WhisperKitBackend's shortest clip is derived from, so audio shorter than it is padded.
    @Test("the window clip the product asks for is a field the decoder still takes")
    func windowClipSurvives() {
        let options = DecodingOptions(windowClipTime: VocabularyPrompt.windowClipTime)

        #expect(options.windowClipTime == VocabularyPrompt.windowClipTime)
    }

    /// The prefill the timestamp rules are told to start sampling after, counted from these.
    @Test("a multilingual decode still prefills the four tokens DecoderPrefill counts without a prompt")
    func prefillLengthIsStillFour() {
        let prefill = DecoderPrefill(
            promptTokens: nil, specialTokenBegin: 50_257, isMultilingual: true)

        #expect(prefill.count == 4)
    }
}
