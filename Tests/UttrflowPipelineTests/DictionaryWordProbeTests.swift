// Tests for trying one dictionary word: the three outcomes, and that a try decodes twice and writes nothing.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
import UttrflowTestSupport

/// A recogniser that hears one phrase with the entry in its prompt and another without, and counts its decodes.
private actor PromptedSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let withoutPrompt: String
    private let withPrompt: String
    private(set) var prompts: [[String]] = []

    init(withoutPrompt: String, withPrompt: String) {
        self.withoutPrompt = withoutPrompt
        self.withPrompt = withPrompt
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        prompts.append(options.vocabulary)
        let text = options.vocabulary.isEmpty ? withoutPrompt : withPrompt
        let words = text.split(separator: " ").map { TranscribedWord(text: String($0), confidence: 0.2) }
        return Transcription(
            text: text,
            segments: [TranscriptionSegment(text: text, start: .zero, end: .seconds(1), words: words)],
            audioDuration: audio.duration)
    }
}

/// A corrector that writes one spelling for one heard word.
private struct OneSpelling: WordCorrecting {
    let heard: String
    let wrote: String

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        transcription.text.split(whereSeparator: \.isWhitespace).enumerated().compactMap {
            $0.element.lowercased().trimmingCharacters(in: .punctuationCharacters) == heard
                ? DictationCorrection(
                    heard: String($0.element), wrote: wrote, wordRange: $0.offset..<($0.offset + 1),
                    entryID: UUID(), reason: .unknown("test"), heardConfidence: 0.2)
                : nil
        }
    }
}

@Suite("Trying a dictionary word: recognition only, with and without the entry")
struct DictionaryWordProbeTests {
    private static let entry = DictionaryEntry(
        word: "Quillon", pronunciation: "quill on", origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
    private static let clip = AudioSamples.canonical(Array(repeating: 0.1, count: 16_000))

    @Test("a word the prompt fixes is recognised from the start, and both decodes run")
    func promptFixes() async throws {
        let speech = PromptedSpeechEngine(
            withoutPrompt: "send it to quill on", withPrompt: "Send it to Quillon.")
        let result = try await DictionaryWordProbe(
            speech: speech, corrector: OneSpelling(heard: "x", wrote: "y")
        )
        .probe(Self.clip, for: Self.entry)
        #expect(result.outcome == .recognisedFromStart)
        #expect(result.withoutEntry == "send it to quill on")
        #expect(await speech.prompts == [[], ["Quillon"]])
    }

    @Test("a word only the correction fixes is recognised after correction")
    func correctionFixes() async throws {
        let speech = PromptedSpeechEngine(
            withoutPrompt: "send it to quillen", withPrompt: "send it to quillen")
        let result = try await DictionaryWordProbe(
            speech: speech, corrector: OneSpelling(heard: "quillen", wrote: "Quillon")
        ).probe(Self.clip, for: Self.entry)
        #expect(result.outcome == .recognisedAfterCorrection)
        #expect(result.corrected == "send it to Quillon")
    }

    @Test("a word neither fixes says what was heard")
    func neitherFixes() async throws {
        let speech = PromptedSpeechEngine(
            withoutPrompt: "send it to pavilion", withPrompt: " send it to pavilion ")
        let result = try await DictionaryWordProbe(
            speech: speech, corrector: OneSpelling(heard: "quillen", wrote: "Quillon")
        ).probe(Self.clip, for: Self.entry)
        #expect(result.outcome == .heardAs("send it to pavilion"))
    }

    @Test("the spelling is matched as whole words, so a longer word does not count")
    func wholeWords() {
        #expect(
            DictionaryWordProbe.outcome(
                of: Self.entry, heard: "Quillons arrived", corrected: "Quillons arrived")
                == .heardAs("Quillons arrived"))
        #expect(
            DictionaryWordProbe.outcome(of: Self.entry, heard: "quillon, then", corrected: "")
                == .recognisedFromStart)
    }

    @Test("with the shipping correction engine, a dictionary of only this entry is what it corrects against")
    func shippingEngine() async throws {
        let speech = PromptedSpeechEngine(withoutPrompt: "pavilion", withPrompt: "pavilion")
        let result = try await DictionaryWordProbe(speech: speech, dictionary: [Self.entry])
            .probe(Self.clip, for: Self.entry)
        #expect(result.corrected == "pavilion")
        #expect(result.outcome == .heardAs("pavilion"))
    }
}

@Suite("Saying a new word once fills \"Say it like\" with the recogniser's own spelling")
struct HeardSpellingTests {
    private static let clip = AudioSamples.canonical(Array(repeating: 0.1, count: 16_000))

    @Test("the offer is the decode without the vocabulary, without its edge punctuation")
    func offersRawDecode() async throws {
        let speech = PromptedSpeechEngine(withoutPrompt: "Quill on.", withPrompt: "Quillon.")
        let corrector = OneSpelling(heard: "x", wrote: "y")
        let offer = try await DictionaryWordProbe(speech: speech, corrector: corrector)
            .heardSpelling(Self.clip, of: "Quillon")
        #expect(offer == .sayItLike("Quill on", heardWordCount: 2))
        #expect(!offer.wasTrimmed)
        #expect(await speech.prompts == [[]])
    }

    @Test("a spelling the recogniser already writes needs no pronunciation")
    func alreadyRecognised() {
        #expect(DictionaryWordProbe.heardSpelling("Quillon.", of: "quillon") == .alreadyRecognised)
    }

    @Test("a four-word decode is cut to the entry limit and says so")
    func trimsVisibly() {
        let offer = DictionaryWordProbe.heardSpelling("quill on the hill", of: "Quillon")
        #expect(offer == .sayItLike("quill on the", heardWordCount: 4))
        #expect(offer.wasTrimmed)
    }

    @Test("silence offers nothing")
    func nothingHeard() {
        #expect(DictionaryWordProbe.heardSpelling(" … ", of: "Quillon") == .nothingHeard)
    }

    @Test("each outcome says one line, and only a miss offers a Say it like")
    func resultRow() {
        #expect(DictionaryProbeOutcome.recognisedFromStart.resultLine == "Recognised from the start")
        #expect(
            DictionaryProbeOutcome.recognisedAfterCorrection.resultLine
                == "Recognised after Uttrflow’s correction")
        #expect(
            DictionaryProbeOutcome.heardAs("nikkel").resultLine
                == "Heard as “nikkel”, and that does not sound like this entry")
        #expect(DictionaryProbeOutcome.heardAs("nikkel").sayItLikeOffer == "nikkel")
        #expect(DictionaryProbeOutcome.heardAs("").sayItLikeOffer == nil)
        #expect(DictionaryProbeOutcome.recognisedFromStart.sayItLikeOffer == nil)
        #expect(DictionaryProbeOutcome.recognisedAfterCorrection.sayItLikeOffer == nil)
    }

    @Test("a Say it fills the field only with heard words, and its line names a trim")
    func sayItRow() {
        #expect(HeardSpelling.alreadyRecognised.resultLine == "Already recognised, no pronunciation needed")
        #expect(HeardSpelling.alreadyRecognised.sayItLikeFill == nil)
        #expect(HeardSpelling.nothingHeard.sayItLikeFill == nil)
        let kept = HeardSpelling.sayItLike("quill on", heardWordCount: 2)
        #expect(kept.sayItLikeFill == "quill on")
        #expect(kept.resultLine == "Heard as \u{201C}quill on\u{201D}")
        let trimmed = DictionaryWordProbe.heardSpelling("quill on the hill", of: "Quillon")
        #expect(trimmed.sayItLikeFill == "quill on the")
        #expect(trimmed.resultLine == "Heard 4 words; kept the first 3, \u{201C}quill on the\u{201D}")
    }
}

@Suite("Trying a dictionary word: listening on the microphone")
struct DictionaryWordListeningTests {
    private static let entry = DictionaryEntry(
        word: "Quillon", pronunciation: "quill on", origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
    private static let clip = AudioSamples.canonical(Array(repeating: 0.1, count: 16_000))

    @Test("a spoken try records, stops and probes the clip, keeping nothing")
    func listens() async throws {
        let microphone = FakeAudioCaptureEngine(stopOutcome: .success(Self.clip))
        let speech = PromptedSpeechEngine(withoutPrompt: "quill on", withPrompt: "Quillon")
        let result = try await DictionaryWordProbe(speech: speech, dictionary: [Self.entry])
            .probe(listeningTo: microphone, for: Self.entry, atMost: .milliseconds(1))
        #expect(result.outcome == .recognisedFromStart)
        #expect(await microphone.calls.events == [.start, .stop])
    }

    @Test("a spoken Say it records once and decodes without the vocabulary")
    func listensForSpelling() async throws {
        let microphone = FakeAudioCaptureEngine(stopOutcome: .success(Self.clip))
        let speech = PromptedSpeechEngine(withoutPrompt: "quill on", withPrompt: "Quillon")
        let offer = try await DictionaryWordProbe(speech: speech, dictionary: [Self.entry])
            .heardSpelling(listeningTo: microphone, of: "Quillon", atMost: .milliseconds(1))
        #expect(offer == .sayItLike("quill on", heardWordCount: 2))
        #expect(await microphone.calls.events == [.start, .stop])
        #expect(await speech.prompts == [[]])
    }

    @Test("a cancelled try discards the clip and decodes nothing")
    func cancelled() async {
        let microphone = FakeAudioCaptureEngine()
        let speech = PromptedSpeechEngine(withoutPrompt: "quill on", withPrompt: "Quillon")
        let probe = DictionaryWordProbe(speech: speech, dictionary: [Self.entry])
        let work = Task {
            try await probe.probe(listeningTo: microphone, for: Self.entry, atMost: .seconds(60))
        }
        while await microphone.state != .recording { await Task.yield() }
        work.cancel()
        #expect(await (try? work.value) == nil)
        #expect(await microphone.calls.events == [.start, .cancel])
        #expect(await speech.prompts.isEmpty)
    }
}
