// Tests that the language tally counts a confident, long-enough dictation once and nothing else.
import Testing

@testable import UttrflowCore

@Suite("The language tally")
struct LanguageSignalsTests {
    private let long = "we should ship the new build to the staging server before lunch today"

    @Test("a confident dictation of enough words counts once under its language code")
    func countsConfidentLongDictation() throws {
        let hindi = try #require(LanguageCode("hi"))
        let english = try #require(LanguageCode("en"))
        let rows =
            LanguageSignals.rows(
                for: long, heardAs: DetectedLanguage(code: english, confidence: 0.95), day: 1)
            + LanguageSignals.rows(for: long, heardAs: DetectedLanguage(code: hindi, confidence: 0.9), day: 1)
            + LanguageSignals.rows(
                for: long, heardAs: DetectedLanguage(code: english, confidence: 0.85), day: 2)
        #expect(LanguageSignals.project(rows) == ["en": 2, "hi": 1])
    }

    @Test("a short, unsure or unreported detection counts nothing")
    func abstains() throws {
        let english = try #require(LanguageCode("en"))
        #expect(
            LanguageSignals.rows(
                for: "yes please", heardAs: DetectedLanguage(code: english, confidence: 0.99), day: 1
            ).isEmpty)
        #expect(
            LanguageSignals.rows(for: long, heardAs: DetectedLanguage(code: english, confidence: 0.5), day: 1)
                .isEmpty)
        #expect(LanguageSignals.rows(for: long, heardAs: DetectedLanguage(code: english), day: 1).isEmpty)
        #expect(LanguageSignals.rows(for: long, heardAs: nil, day: 1).isEmpty)
    }

    @Test("a verdict with no confidence counts only from a long dictation")
    func unreportedConfidenceNeedsLength() throws {
        let english = try #require(LanguageCode("en"))
        let engine = DetectedLanguage(code: english)
        let longer = Array(repeating: long, count: 2).joined(separator: " ")
        #expect(LanguageSignals.rows(for: long, heardAs: engine, day: 1).isEmpty)
        #expect(
            LanguageSignals.project(LanguageSignals.rows(for: longer, heardAs: engine, day: 1)) == ["en": 1])
    }
}
