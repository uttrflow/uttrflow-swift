import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The romaniser against the corpus's romanised references, and English left byte for byte as it was.
@Suite("The romaniser over the corpus")
struct RomaniserCorpusTests {
    /// Every committed passage written in both scripts.
    static let parallel = TranscriptionCorpus.all.filter { $0.devanagari != nil }

    /// Word and character accuracy of `romanise` over every parallel passage, pooled.
    static func accuracy(_ romanise: (String) -> String) -> (words: Double, characters: Double) {
        let normaliser = TextNormaliser.standard
        var wordErrors = 0
        var wordCount = 0
        var characterErrors = 0
        var characterCount = 0
        for passage in parallel {
            guard let devanagari = passage.devanagari else { continue }
            let reference = normaliser.words(passage.romanised)
            let hypothesis = normaliser.words(romanise(devanagari))
            let words = WordErrorRate.measure(reference: reference, hypothesis: hypothesis)
            wordErrors += words.errors
            wordCount += words.referenceWordCount
            let characters = WordErrorRate.measure(
                reference: reference.joined(separator: " ").map(String.init),
                hypothesis: hypothesis.joined(separator: " ").map(String.init))
            characterErrors += characters.errors
            characterCount += characters.referenceWordCount
        }
        return (
            1 - Double(wordErrors) / Double(wordCount), 1 - Double(characterErrors) / Double(characterCount)
        )
    }

    @Test("covers the twelve Hindi and Hinglish passages")
    func coversTheParallelPassages() {
        #expect(Self.parallel.count == 12)
    }

    /// Measured at 97.9% of words and 99.4% of characters, against 42.7% and 84.5% letter by letter; see `Docs/latin-output.md`.
    @Test("romanises the corpus as its references spell it, well above letter-by-letter transliteration")
    func romanisesAsTyped() {
        let romaniser = Self.accuracy { Romaniser.romanised($0) }
        let letterByLetter = Self.accuracy(\.transliteratedToLatin)

        #expect(romaniser.words >= 0.96, "word accuracy \(romaniser.words)")
        #expect(romaniser.characters >= 0.99, "character accuracy \(romaniser.characters)")
        #expect(romaniser.words > letterByLetter.words + 0.3, "letter by letter \(letterByLetter.words)")
    }

    @Test("leaves every English passage and every English expectation byte for byte as written")
    func leavesEnglishAlone() {
        let english =
            TranscriptionCorpus.all.filter { $0.devanagari == nil }.map(\.romanised)
            + EvaluationCorpus.all.filter { $0.language != .hindi }.flatMap { [$0.spoken, $0.expected] }
        #expect(english.count > 100)
        for text in english {
            #expect(LatinScript.enforced(text) == text)
            #expect(Romaniser.romanised(text) == text)
        }
    }

    @Test("gives every English case the rules' answer from before romanising existed")
    func rulesUnchangedOnEnglish() async throws {
        for testCase in EvaluationCorpus.all where testCase.language != .hindi {
            let request = testCase.transformationRequest()
            let formatter = DestinationFormatter.standard(for: request.situation.destination)
            let unromanised = CleaningPipeline.standard(for: formatter, situation: request.situation)
                .run(Draft(transcription: request.transcription)).text
            #expect(try await RuleBasedTransformer().transform(request).text == unromanised, "\(testCase.id)")
        }
    }

    @Test("writes every Hindi case of the clean-up corpus in Latin letters on the rules path")
    func rulesWriteHindiInLatin() async throws {
        for testCase in EvaluationCorpus.all where testCase.language == .hindi {
            let text = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
            #expect(
                LatinScript.isLatin(text) && !Romaniser.containsDevanagari(text), "\(testCase.id): \(text)")
        }
    }
}
