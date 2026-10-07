// Tests the per-recording decode dump that fits read instead of re-decoding.
import Foundation
import Testing

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
}
