// Measures who should own the question mark on recorded clips. See Docs/question-mark-owner.md.
import Foundation
import Testing
import UttrflowCore
import UttrflowEval
import WhisperKit

@testable import UttrflowSpeech

/// One recorded clip and the sentence a person actually said, with its true closing mark.
struct QuestionClip: Equatable {
    let audio: String
    let truth: String

    /// Reads `audio<TAB>truth` lines, skipping blanks and `#` comments.
    static func read(_ listing: String) -> [QuestionClip] {
        listing.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard fields.count == 2, !line.hasPrefix("#") else { return nil }
            return QuestionClip(audio: fields[0], truth: fields[1].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Whether the truth closes on a question mark.
    var isQuestion: Bool { truth.hasSuffix("?") }
}

/// What the probe reads off one decode.
enum QuestionEvidence {
    /// The recogniser's closing mark and, when both were among the leaders there, P("?") against P(".").
    static func decoderMark(
        tokens: [Int], logProbs: [[Int: Float]], question: Int, stop: Int
    ) -> (asks: Bool, probability: Double?) {
        guard let last = tokens.lastIndex(where: { $0 == question || $0 == stop }) else {
            return (false, nil)
        }
        let leaders = last < logProbs.count ? logProbs[last] : [:]
        let probability = leaders[question].flatMap { asked in
            leaders[stop].map { stopped in 1 / (1 + exp(Double(stopped - asked))) }
        }
        return (tokens[last] == question, probability)
    }

    /// Whether `QuestionShape` reads the last sentence of `text`, its marks taken off, as a question.
    static func rulesAsk(_ text: String) -> Bool {
        let shapes = text.split(whereSeparator: \.isWhitespace).map { WordShape(String($0)) }
        let earlier = shapes.dropLast().lastIndex(where: \.endsSentence).map { $0 + 1 } ?? 0
        let sentence = shapes[earlier...].map { WordShape($0.prefix + $0.core) }
        return !sentence.isEmpty && QuestionShape.asks(Array(sentence))
    }
}

@Suite("Reading the question-mark evidence")
struct QuestionEvidenceTests {
    @Test("reads clips from a tab-separated listing")
    func readsListing() {
        let clips = QuestionClip.read("# clip\ta.wav\nb.wav\tIs it done?\n\nc.wav\tIt is done.\n")
        #expect(
            clips == [
                QuestionClip(audio: "b.wav", truth: "Is it done?"),
                QuestionClip(audio: "c.wav", truth: "It is done."),
            ])
        #expect(clips.map(\.isQuestion) == [true, false])
    }

    @Test("takes the last closing mark and weighs the question mark against the full stop")
    func decoderMark() throws {
        let mark = QuestionEvidence.decoderMark(
            tokens: [5, 9, 7], logProbs: [[5: 0], [9: log(0.75), 8: log(0.25)], [7: 0]], question: 9, stop: 8)
        #expect(mark.asks)
        #expect(abs(try #require(mark.probability) - 0.75) < 1e-6)
        #expect(
            QuestionEvidence.decoderMark(tokens: [5], logProbs: [[5: 0]], question: 9, stop: 8) == (
                false, nil
            ))
        #expect(
            QuestionEvidence.decoderMark(tokens: [8], logProbs: [[8: 0]], question: 9, stop: 8).probability
                == nil)
    }

    @Test("the rules read only the last sentence, without its marks")
    func rulesReadTheLastSentence() {
        #expect(QuestionEvidence.rulesAsk("I sent it. Did you get it."))
        #expect(!QuestionEvidence.rulesAsk("Did you get it? I sent it."))
        #expect(!QuestionEvidence.rulesAsk(""))
    }
}

/// Where the probe reads its listing from.
enum QuestionProbeInputs {
    static let listing = ProcessInfo.processInfo.environment["UTTRFLOW_QUESTION_CLIPS"]
    static var isRunnable: Bool {
        listing.map(FileManager.default.fileExists(atPath:)) == true
            && FileManager.default.fileExists(atPath: ProbeInputs.modelFolder.path)
    }
}

/// The shipping model on recorded clips, run only when `UTTRFLOW_QUESTION_CLIPS` names a listing.
@Suite(
    "Probing who owns the question mark on the shipping model",
    .enabled(if: QuestionProbeInputs.isRunnable, "set UTTRFLOW_QUESTION_CLIPS and install the shipping model")
)
struct QuestionMarkOwnerProbe {
    @Test("prints precision, recall and the false-question rate per owner, with intervals")
    func probe() async throws {
        let listing = try String(contentsOfFile: try #require(QuestionProbeInputs.listing), encoding: .utf8)
        let kit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: ProbeInputs.modelFolder.path, tokenizerFolder: ProbeInputs.modelFolder,
                verbose: false, logLevel: .error, prewarm: true, load: true, download: false))
        kit.textDecoder = LanguageHeldDecoder(wrapping: kit.textDecoder, languages: LanguageCode.transcribed)
        let tokenizer = try #require(kit.tokenizer)
        let question = try #require(tokenizer.convertTokenToId("?"))
        let stop = try #require(tokenizer.convertTokenToId("."))
        var cases: [QuestionMarkCase] = []
        for clip in QuestionClip.read(listing) {
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: clip.audio)
            let results = try await kit.transcribe(
                audioArray: samples, decodeOptions: VocabularyPrompt.decodingOptions(languageHint: .english))
            let segments = results.flatMap(\.segments)
            let mark = QuestionEvidence.decoderMark(
                tokens: segments.flatMap(\.tokens), logProbs: segments.flatMap(\.tokenLogProbs),
                question: question, stop: stop)
            let text = results.map(\.text).joined(separator: " ")
            cases.append(
                QuestionMarkCase(
                    isQuestion: clip.isQuestion, decoderAsks: mark.asks,
                    decoderQuestionProbability: mark.probability, rulesAsk: QuestionEvidence.rulesAsk(text)))
        }
        #expect(!cases.isEmpty)
        print("PROBE question-mark owner over \(cases.count) clips\n\(QuestionMarkOwnership(cases).table)")
    }
}
