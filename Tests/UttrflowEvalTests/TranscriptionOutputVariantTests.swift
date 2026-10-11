import Foundation
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Transcription output spelling variants")
struct TranscriptionOutputVariantTests {
    private func passage(
        reference: String, language: TranscriptionCase.Language = .hindi, id: String = "variant-output"
    ) -> TranscriptionCase {
        TranscriptionCase(
            id: id, language: language, stressor: .everyday,
            romanised: reference, devanagari: "हाँ ठीक है")
    }

    @Test("attested Hindi variants leave recognition and output error free")
    func attestedVariants() {
        let score = TranscriptionScorer.score("हाँ ठीक है", against: passage(reference: "Haan theek hai"))
        #expect(score.wordErrorRate?.errors == 0)
        #expect(score.outputWordErrorRate?.errors == 0)
        #expect(score.outputWordErrorRate?.referenceWordCount == 3)
    }

    @Test(
        "unlisted spellings and English terms remain exact in Hindi output",
        arguments: [
            ("thk", "thik"), ("colour", "color"), ("h_ai", "hai"), ("hé", "he"), ("1.2", "12"),
        ])
    func exactFallback(words: (String, String)) {
        let reference = "Haan theek hai " + words.0
        let transcript = "हाँ ठीक है " + words.1
        let score = TranscriptionScorer.score(transcript, against: passage(reference: reference))
        #expect(score.outputWordErrorRate?.substitutions == 1)
        #expect(score.outputWordErrorRate?.referenceWordCount == 4)
    }

    @Test("the twelve Hindi and Hinglish passages carry both rates and their output instrument")
    func corpusOutputRates() throws {
        let passages = TranscriptionCorpus.all.filter { $0.language != .english }
        #expect(passages.count == 12)
        for passage in passages {
            let transcript = try #require(passage.reference(in: .devanagari))
            let score = TranscriptionScorer.score(transcript, against: passage)
            #expect(score.wordErrorRate?.errors == 0)
            let output = try #require(score.outputWordErrorRate)
            #expect(output.referenceWordCount == TextNormaliser.standard.words(passage.romanised).count)
            #expect(score.outputNormalisation == TranscriptionScorer.outputNormalisation)
            let decoded = try JSONDecoder().decode(PassageScore.self, from: JSONEncoder().encode(score))
            #expect(decoded.outputNormalisation == score.outputNormalisation)
        }
    }

    @Test("dropping a vowel sign worsens only the output gate against a fixed reference")
    func vowelSignBreakFailsGate() throws {
        #expect(LatinScript.enforced("हाँ थिक है") == "Haan thik hai")
        #expect(LatinScript.enforced("हाँ थक है") == "Haan thak hai")
        let pairs = (1...3).map { index in
            let fixed = passage(reference: "Haan theek hai", id: "vowel-output-\(index)")
            return (
                correct: TranscriptionScorer.score("हाँ थिक है", against: fixed),
                broken: TranscriptionScorer.score("हाँ थक है", against: fixed)
            )
        }
        let pair = try #require(pairs.first)
        #expect(pair.correct.wordErrorRate?.substitutions == 1)
        #expect(pair.correct.wordErrorRate?.rate == 1.0 / 3)
        #expect(pair.broken.wordErrorRate?.substitutions == 1)
        #expect(pair.correct.wordErrorRate?.rate == pair.broken.wordErrorRate?.rate)
        #expect(pair.correct.outputWordErrorRate?.errors == 0)
        #expect(pair.broken.outputWordErrorRate?.substitutions == 1)
        let baseline = AccuracyBaseline.capture(
            TranscriptionReport(label: "probe", scores: pairs.map(\.correct)))
        let comparison = baseline.compare(
            with: TranscriptionReport(label: "probe", scores: pairs.map(\.broken)))
        #expect(comparison.verdict == .worsened)
        #expect(comparison.failsGate)
    }

    @Test("legacy exact baselines are refused against variant scoring and their JSON remains readable")
    func legacyInstrumentIsIncomparable() throws {
        let score = TranscriptionScorer.score("हाँ ठीक है", against: passage(reference: "Haan theek hai"))
        let report = TranscriptionReport(label: "probe", scores: [score])
        let fresh = AccuracyBaseline.capture(report)
        let data = try JSONEncoder().encode(fresh)
        var stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entries = try #require(stored["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "outputNormalisation")
        stored["entries"] = entries
        let legacy = try JSONDecoder().decode(
            AccuracyBaseline.self, from: JSONSerialization.data(withJSONObject: stored))
        #expect(legacy.entries[0].outputNormalisation == nil)
        let comparison = legacy.compare(with: report)
        #expect(comparison.verdict == .incomparable)
        #expect(comparison.reason?.contains("output normalisation changed") == true)
        let reread = try JSONDecoder().decode(AccuracyBaseline.self, from: data)
        #expect(reread.entries[0].outputNormalisation == TranscriptionScorer.outputNormalisation)
        #expect(reread.compare(with: report).verdict == .unchanged)
    }
}
