// Tests the hand-written transcription corpus for mistakes that would mis-score.
import Testing

@testable import UttrflowEval

/// Checks the passages for the mistakes that show up months later as "always scores badly on Hindi".
@Suite("Transcription corpus")
struct TranscriptionCorpusTests {
    private let normaliser = TextNormaliser.standard

    @Test("gives every passage a unique id")
    func uniqueIDs() {
        #expect(Set(TranscriptionCorpus.all.map(\.id)).count == TranscriptionCorpus.all.count)
    }

    @Test("covers all three of the product's languages")
    func coversEveryLanguage() {
        for language in TranscriptionCase.Language.allCases {
            #expect(
                TranscriptionCorpus.cases(in: language).count >= 5,
                "\(language.rawValue) has too few passages to say anything")
        }
    }

    /// A language measured only on easy sentences is a language nobody has measured.
    @Test("stresses every language with more than everyday speech")
    func everyLanguageIsStressed() {
        for language in TranscriptionCase.Language.allCases {
            let stressors = Set(TranscriptionCorpus.cases(in: language).map(\.stressor))
            #expect(stressors.count >= 3, "\(language.rawValue) only covers \(stressors.count) stressor(s)")
        }
    }

    @Test("uses every stressor it defines")
    func everyStressorAppears() {
        // `.other` exists for catalogue samples only; a hand-written passage must name its stress.
        for stressor in TranscriptionCase.Stressor.allCases where stressor != .other {
            #expect(
                !TranscriptionCorpus.cases(stressing: stressor).isEmpty,
                "nothing stresses \(stressor.rawValue)")
        }
    }

    /// The product's output is romanised Hinglish, never Devanagari, so the reference must be too.
    @Test("keeps every romanised reference free of Devanagari")
    func romanisedIsRomanised() {
        for passage in TranscriptionCorpus.all {
            #expect(
                Script.of(passage.romanised) == .latin, "\(passage.id) has Devanagari in its romanised form")
        }
    }

    @Test("gives every Hindi and Hinglish passage a Devanagari form to be heard as")
    func devanagariFormsExist() {
        for passage in TranscriptionCorpus.all {
            let needsOne = passage.language != .english
            #expect(
                (passage.devanagari != nil) == needsOne,
                "\(passage.id) has the wrong forms for a \(passage.language.rawValue) passage")
            if needsOne {
                #expect(
                    Script.of(passage.prompt) == .devanagari, "\(passage.id) is not prompted in Devanagari")
            }
        }
    }

    /// Two forms of one reading must have the same word count, or the script answered in changes the score.
    @Test("writes both forms of a passage with the same number of words")
    func formsAreParallel() {
        for passage in TranscriptionCorpus.all {
            guard let devanagari = passage.devanagari else { continue }
            #expect(
                normaliser.words(devanagari).count == normaliser.words(passage.romanised).count,
                """
                \(passage.id): \(normaliser.words(devanagari).count) Devanagari words against \
                \(normaliser.words(passage.romanised).count) romanised
                """)
        }
    }

    @Test("puts every required term in every form of its passage")
    func requiredTermsAppearInBothForms() {
        for passage in TranscriptionCorpus.all {
            for form in passage.forms {
                let words = normaliser.words(form)
                for term in passage.mustKeep {
                    #expect(
                        Scorer.containsPhrase(normaliser.words(term), in: words),
                        "\(passage.id) requires '\(term)', which is not in one of its own forms")
                }
            }
        }
    }

    /// A passage that fails this is unwinnable, and every engine would be marked down for the corpus's fault.
    @Test("scores a perfect transcript of either form at zero")
    func perfectTranscriptsScoreZero() {
        for passage in TranscriptionCorpus.all {
            for form in passage.forms {
                let score = TranscriptionScorer.score(form, against: passage)
                #expect(score.wordErrorRate?.rate == 0, "\(passage.id) cannot be transcribed perfectly")
                #expect(score.lost.isEmpty, "\(passage.id) loses \(score.lost) to its own text")
                #expect(!score.isUpperBound, "\(passage.id) had to be transliterated to score itself")
            }
        }
    }

    @Test("has something for the recogniser to work with in every passage")
    func passagesAreLongEnough() {
        for passage in TranscriptionCorpus.all {
            #expect(TranscriptionCorpus.wordCount(of: passage) >= 25, "\(passage.id) is too short to measure")
        }
    }

    /// The session is sold as "about twenty minutes", so the corpus must not grow into an afternoon.
    @Test("takes about twenty minutes to read")
    func readingTimeIsAsPromised() {
        let minutes = TranscriptionCorpus.estimatedReadingTime.components.seconds / 60
        #expect((10...25).contains(minutes), "reading the corpus is estimated at \(minutes) minutes")
        #expect(TranscriptionCorpus.estimatedReadingTime(of: []).components.seconds == 0)
    }

    @Test("finds a passage by id, and says when there is none")
    func lookup() {
        #expect(TranscriptionCorpus.passage("en-standup")?.language == .english)
        #expect(TranscriptionCorpus.passage("no-such-passage") == nil)
    }

    @Test("hints Hindi for Hinglish, because that is the language it is led by")
    func languageCodes() {
        #expect(TranscriptionCase.Language.english.code == .english)
        #expect(TranscriptionCase.Language.hindi.code == .hindi)
        #expect(TranscriptionCase.Language.hinglish.code == .hindi)
    }
}
