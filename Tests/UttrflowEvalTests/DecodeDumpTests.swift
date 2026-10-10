// Tests the per-recording decode dump that fits read instead of re-decoding.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Decode dumps")
struct DecodeDumpTests {
    private let engine = DecodeEngineIdentity(
        engineVersion: "1.1.0", weightsRevision: "w1", tokenizerRevision: "t1",
        promptDigest: "sha256:p", optionsDigest: "sha256:o")

    private func temporaryCorpus() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "decode-dumps-\(UUID().uuidString)")
    }

    private func dump(words: Int, under engine: DecodeEngineIdentity? = nil) -> DecodeDump {
        let decoded = (0..<words).map { index in
            DecodedWord(
                text: "word\(index)", start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25,
                logProbability: -0.12, margin: 1.5, entropy: 0.4,
                alternatives: [
                    DecodeAlternative(text: "ward\(index)", logProbability: -1.6),
                    DecodeAlternative(text: "world\(index)", logProbability: -2.9),
                ])
        }
        return DecodeDump(
            recordingIdentity: "sha256:abc", engine: engine ?? self.engine, fallbackRung: 1, words: decoded)
    }

    /// A stand-in fit: the threshold that flags the lowest-margin quarter of words.
    private func fit(_ dumps: [DecodeDump]) -> Double? {
        let margins = dumps.flatMap(\.words).compactMap(\.margin).sorted()
        return margins.isEmpty ? nil : margins[margins.count / 4]
    }

    @Test("a dump reads back exactly as written")
    func roundTrip() throws {
        let store = DecodeDumpStore(corpusDirectory: temporaryCorpus())
        let written = dump(words: 3)
        try store.save(written)
        #expect(try store.dumps(decodedUnder: engine) == [written])
    }

    @Test("fitting from dumps gives the same result on two runs with no decoder loaded")
    func fitIsReproducible() throws {
        let store = DecodeDumpStore(corpusDirectory: temporaryCorpus())
        try store.save(dump(words: 20))
        let first = fit(try store.dumps(decodedUnder: engine))
        let second = fit(try store.dumps(decodedUnder: engine))
        #expect(first != nil)
        #expect(first == second)
    }

    @Test("a re-decode writes a second file and never replaces the first")
    func neverOverwrites() throws {
        let store = DecodeDumpStore(corpusDirectory: temporaryCorpus())
        let first = try store.save(dump(words: 2))
        let second = try store.save(dump(words: 5))
        #expect(first.url != second.url)
        #expect(try store.dumps(decodedUnder: engine).map(\.words.count).sorted() == [2, 5])
    }

    @Test("a dump made under another engine identity is refused, naming the field")
    func refusesOtherEngine() throws {
        let store = DecodeDumpStore(corpusDirectory: temporaryCorpus())
        let other = DecodeEngineIdentity(
            engineVersion: "1.1.0", weightsRevision: "w1", tokenizerRevision: "t2",
            promptDigest: "sha256:p", optionsDigest: "sha256:o")
        try store.save(dump(words: 1, under: other))
        #expect(
            throws: DecodeDumpError.engineMismatch(
                recordingIdentity: "sha256:abc", field: "tokenizerRevision")
        ) {
            try store.dumps(decodedUnder: engine)
        }
    }

    @Test("names each differing field, and none for a match")
    func differingField() {
        #expect(engine.differingField(from: engine) == nil)
        let prompt = DecodeEngineIdentity(
            engineVersion: "1.1.0", weightsRevision: "w1", tokenizerRevision: "t1",
            promptDigest: "sha256:q", optionsDigest: "sha256:o")
        #expect(engine.differingField(from: prompt) == "promptDigest")
    }

    @Test("a 686-word corpus dumps to under 1 MB")
    func sizeBound() throws {
        let store = DecodeDumpStore(corpusDirectory: temporaryCorpus())
        let saved = try store.save(dump(words: 686))
        #expect(saved.bytes < 1_000_000)
    }

    @Test("dumps live inside the local corpus directory")
    func livesInCorpus() {
        let corpus = temporaryCorpus()
        #expect(
            DecodeDumpStore(corpusDirectory: corpus).directory.path
                == corpus.appending(path: "decode-dumps").path)
    }

    private func transcription(fallbacks: Int) -> Transcription {
        let tokened = TranscribedWord(
            text: "hello", confidence: 0.9, start: .milliseconds(100), end: .milliseconds(400),
            tokens: [
                TokenEvidence(logProb: -0.1, alternatives: [-2.5, -3.0]),
                TokenEvidence(logProb: -0.4, alternatives: [-1.2]),
            ])
        let reported = TranscribedWord(text: "world", confidence: 0.5)
        return Transcription(
            text: "hello world",
            segments: [
                TranscriptionSegment(
                    text: "hello world", start: .zero, end: .seconds(1), words: [tokened, reported])
            ],
            effort: DecodeEffort(fallbacks: fallbacks))
    }

    @Test("a transcription's words, token evidence and fallback rung go into its dump")
    func fromTranscription() throws {
        let made = DecodeDump(
            recordingIdentity: "sha256:abc", engine: engine, transcription: transcription(fallbacks: 2))
        #expect(made.fallbackRung == 2)
        #expect(made.words.map(\.text) == ["hello", "world"])
        let hello = try #require(made.words.first)
        #expect(hello.start == 0.1 && hello.end == 0.4)
        #expect(hello.logProbability == -0.1)
        #expect(abs((hello.margin ?? 0) - 2.4) < 1e-9)
        let entropy = try #require(hello.entropy)
        #expect(entropy > 0)
        #expect(hello.evidence.map(\.logProb) == [-0.1, -0.4])
        let world = try #require(made.words.last)
        #expect(world.tokens == nil && world.margin == nil && world.entropy == nil)
        #expect(abs(world.logProbability - log(0.5)) < 1e-12)
    }

    @Test("a dump written before tokens were kept still reads, with no tokens")
    func readsDumpWithoutTokens() throws {
        let json = Data(
            #"{"text":"a","start":0,"end":0.2,"logProbability":-0.3,"margin":1.0}"#.utf8)
        let word = try JSONDecoder().decode(DecodedWord.self, from: json)
        #expect(word.tokens == nil)
        #expect(word.evidence.isEmpty)
    }

    @Test("a stored decode gives a fit the same words and evidence as the live one, run after run")
    func storedMatchesLive() throws {
        let store = DecodeDumpStore(corpusDirectory: temporaryCorpus())
        let live = transcription(fallbacks: 0)
        try store.save(DecodeDump(recordingIdentity: "sha256:abc", engine: engine, transcription: live))
        let liveHeard = DecodeDump.heard(in: live.segments.flatMap(\.words).map(DecodedWord.init))
        let first = try store.dumps(decodedUnder: engine).flatMap(\.heard)
        let second = try store.dumps(decodedUnder: engine).flatMap(\.heard)
        #expect(first.map(\.word) == ["hello", "world"])
        #expect(first.map(\.word) == liveHeard.map(\.word) && first.map(\.tokens) == liveHeard.map(\.tokens))
        #expect(first.map(\.tokens) == second.map(\.tokens))
        #expect(first.map(\.tokens) == live.segments.flatMap(\.words).map(\.tokens))
        let means = first.map { WordDoubtFeature.mean.certainty(of: $0.tokens) }
        #expect(
            means == live.segments.flatMap(\.words).map { WordDoubtFeature.mean.certainty(of: $0.tokens) })
    }

    @Test("an identity digest names its text without holding it, and differs when the text does")
    func identityDigest() {
        let digest = DecodeEngineIdentity.digest(of: "temperature 0")
        #expect(digest.hasPrefix("sha256:") && !digest.contains("temperature"))
        #expect(digest == DecodeEngineIdentity.digest(of: "temperature 0"))
        #expect(digest != DecodeEngineIdentity.digest(of: "temperature 0.2"))
    }
}
