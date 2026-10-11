// Tests the per-layer ablation over stored decodes: which recordings it reads and the table it prints.
import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

@Suite("The per-layer ablation on recorded decodes")
struct LayerAblationTests {
    private let engine = DecodeEngineIdentity(
        engineVersion: "1.1.0", weightsRevision: "w1", tokenizerRevision: "t1",
        promptDigest: "sha256:p", optionsDigest: "sha256:o")

    private static let rules = TransformerRouter(
        engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "layer-ablation-\(UUID().uuidString)")
    }

    private func recording(_ id: String, identity: String?) throws -> RecordedPassage {
        let passage = try #require(TranscriptionCorpus.all.first { $0.id == id })
        return RecordedPassage(
            passage: passage, recordedAt: Date(timeIntervalSince1970: 0), durationSeconds: 10,
            sampleRate: 16_000,
            recordingIdentity: identity)
    }

    private func dump(of recording: RecordedPassage, under engine: DecodeEngineIdentity) -> DecodeDump {
        let words = recording.passage.romanised.split(separator: " ").enumerated().map { index, word in
            DecodedWord(
                text: " " + word, start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25,
                logProbability: -0.1,
                tokens: [DecodedToken(logProbability: -0.1, alternatives: [-2.0, -3.0])])
        }
        return DecodeDump(
            recordingIdentity: recording.recordingIdentity ?? "", engine: engine, fallbackRung: 0,
            words: words)
    }

    @Test("reads a dump back as the words and token evidence the recogniser reported")
    func dumpIsATranscription() throws {
        let read = dump(of: try recording("en-people", identity: "sha256:a"), under: engine).transcription
        let words = try #require(read.segments.first?.words)
        #expect(read.text == words.map(\.text).joined(separator: " "))
        #expect(
            words.allSatisfy { !$0.tokens.isEmpty && $0.text == $0.text.trimmingCharacters(in: .whitespaces) }
        )
        #expect(
            DecodeDump(recordingIdentity: "x", engine: engine, fallbackRung: 0, words: []).transcription.text
                == "")
    }

    @Test("measures only English test-side recordings that have a kept decode, using the first take")
    func choosesTheTestSide() throws {
        let test = try recording("en-people", identity: "sha256:a")
        let fit = try recording("en-standup", identity: "sha256:b")
        let hindi = try recording("hi-people", identity: "sha256:c")
        let unidentified = try recording("en-versions", identity: nil)
        let undecoded = try recording("en-versions", identity: "sha256:d")
        let second = DecodeDump(recordingIdentity: "sha256:a", engine: engine, fallbackRung: 0, words: [])
        let subjects = LayerAblation.subjects(
            of: [test, fit, hindi, unidentified, undecoded],
            decoded: [
                dump(of: test, under: engine), second, dump(of: fit, under: engine),
                dump(of: hindi, under: engine),
            ])
        #expect(subjects.map(\.testCase.id) == [test.id])
        #expect(subjects.first?.testCase.expected == test.passage.romanised)
        #expect(subjects.first?.heard.text.isEmpty == false)
    }

    @Test("runs one path per default-on layer and no pair")
    func onePathPerLayer() {
        let layers = QualityLayer.allCases.filter(\.defaultOn)
        #expect(LayerAblation.paths == layers.map { [$0] })
    }

    @Test("prints the contribution table naming every default-on layer, from a corpus on disk")
    func reportsFromDisk() async throws {
        let corpus = directory()
        let test = try recording("en-people", identity: "sha256:a")
        try TranscriptionCorpusStore(directory: corpus).save(test, audio: Data())
        try DecodeDumpStore(corpusDirectory: corpus).save(dump(of: test, under: engine))
        let report = try await LayerAblation.report(corpus: corpus, engineVersion: nil, cleaner: Self.rules)
        #expect(report.contains("1 English test-side recordings"))
        #expect(report.contains("## Each layer's marginal contribution"))
        for layer in QualityLayer.allCases where layer.defaultOn {
            #expect(report.contains("| \(layer.rawValue) |"), "\(layer.rawValue) is missing from the table")
        }
    }

    @Test("says what is missing when no test-side recording has a decode")
    func refusesAnEmptyCorpus() async {
        await #expect(throws: LayerAblation.Refusal.nothingToMeasure) {
            try await LayerAblation.report(corpus: directory(), engineVersion: nil, cleaner: Self.rules)
        }
        #expect(LayerAblation.Refusal.nothingToMeasure.description.contains("transcribe"))
    }

    @Test("names the engines when the decodes were made under several")
    func severalEngines() async throws {
        let corpus = directory()
        let test = try recording("en-people", identity: "sha256:a")
        let other = DecodeEngineIdentity(
            engineVersion: "2.0.0", weightsRevision: "w1", tokenizerRevision: "t1",
            promptDigest: "sha256:p", optionsDigest: "sha256:o")
        let store = DecodeDumpStore(corpusDirectory: corpus)
        try store.save(dump(of: test, under: engine))
        try store.save(dump(of: test, under: other))
        await #expect(throws: LayerAblation.Refusal.self) {
            try await LayerAblation.report(corpus: corpus, engineVersion: nil, cleaner: Self.rules)
        }
        #expect(try store.dumps(engineVersion: "2.0.0").map(\.engine) == [other])
        #expect(
            DecodeDumpError.severalEngines(versions: ["1.1.0", "2.0.0"]).description
                == "decodes under 2 engines (1.1.0; 2.0.0); name one with --engine-version")
    }
}
