import UttrflowCore
import Testing

@testable import UttrflowEval

@Suite("Transcription scorer")
struct TranscriptionScorerTests {
    private let english = TranscriptionCase(
        id: "sample-en", language: .english, stressor: .digits,
        romanised: "We are pinning Python 3.11 on port 8080",
        mustKeep: ["Python 3.11", "8080"]
    )

    private let hindi = TranscriptionCase(
        id: "sample-hi", language: .hinglish, stressor: .everyday,
        romanised: "Kal ka deploy ho gaya hai",
        devanagari: "कल का deploy हो गया है",
        mustKeep: ["deploy"]
    )

    @Test("scores a perfect transcript at zero and keeps what was required")
    func perfect() {
        let score = TranscriptionScorer.score(english.romanised, against: english)
        #expect(score.wordErrorRate?.rate == 0)
        #expect(score.keptEverythingRequired)
        #expect(score.answeredIn == .latin)
        #expect(score.scoredAgainst == .latin)
        #expect(!score.isUpperBound)
        #expect(score.failure == nil)
    }

    @Test("forgives case and punctuation, which are not mishearings")
    func surfaceDifferences() {
        let score = TranscriptionScorer.score(
            "we are pinning python 3.11, on port 8080.", against: english)
        #expect(score.wordErrorRate?.rate == 0)
    }

    @Test("counts a misheard term as an error and reports it as lost")
    func lostTerm() {
        let score = TranscriptionScorer.score(
            "We are pinning Python 3.12 on port 8080", against: english)
        #expect(score.wordErrorRate?.substitutions == 1)
        #expect(score.lost == ["Python 3.11"])
        #expect(!score.keptEverythingRequired)
    }

    /// Whisper answers Hindi in Devanagari. Scored against the Devanagari reading of the
    /// passage, a correct transcript is correct — and against the romanised one it would
    /// have looked like a total failure.
    @Test("scores a Devanagari transcript against the Devanagari reading")
    func devanagariAnswer() {
        let score = TranscriptionScorer.score(hindi.prompt, against: hindi)
        #expect(score.wordErrorRate?.rate == 0)
        #expect(score.answeredIn == .devanagari)
        #expect(score.scoredAgainst == .devanagari)
        #expect(!score.isUpperBound)
        #expect(score.lost.isEmpty)
    }

    @Test("scores the same passage romanised against the romanised reading")
    func romanisedAnswer() {
        let score = TranscriptionScorer.score(hindi.romanised, against: hindi)
        #expect(score.wordErrorRate?.rate == 0)
        #expect(score.answeredIn == .latin)
        #expect(score.scoredAgainst == .latin)
    }

    /// An English passage that comes back in Devanagari is a real failure and worth
    /// measuring, but there is no Devanagari reading of it to measure against — so the
    /// transcript is romanised and the score is flagged as an upper bound.
    @Test("transliterates only when there is no reference in the answered script")
    func transliteratedFallback() {
        let score = TranscriptionScorer.score("पोर्ट", against: english)
        #expect(score.answeredIn == .devanagari)
        #expect(score.scoredAgainst == .latin)
        #expect(score.isUpperBound)
        #expect(score.wordErrorRate != nil)
    }

    /// An unreadable recording is the harness's fault. Scoring it would charge the engine
    /// for a file it was never handed.
    @Test("refuses to score a passage whose audio could not be read")
    func unreadableAudioIsNotScored() {
        let score = TranscriptionScorer.score(
            "", against: english, failure: .audioUnreadable("no such file"))
        #expect(score.wordErrorRate == nil)
        #expect(score.failure?.kind == .audioUnreadable)
        #expect(score.failure?.detail == "no such file")
    }

    /// An engine that ran and heard nothing has produced a measurable result: every word
    /// deleted.
    @Test("scores a failed engine at a complete loss")
    func engineFailureIsScored() {
        let score = TranscriptionScorer.score(
            "", against: english, failure: .engineFailed("model would not load"))
        #expect(score.wordErrorRate?.rate == 1)
        #expect(score.wordErrorRate?.deletions == 8)
        #expect(score.failure?.kind == .engineFailed)
        #expect(score.lost == ["Python 3.11", "8080"])
    }

    @Test("says what the failure was, whatever kind it is")
    func failureDetails() {
        #expect(TranscriptionFailure.recognisedNothing.detail == "the engine returned nothing")
        #expect(TranscriptionFailure.recognisedNothing.isScorable)
        #expect(!TranscriptionFailure.audioUnreadable("gone").isScorable)
        #expect(TranscriptionFailure.engineFailed("boom").isScorable)
    }

    /// A rate without its normalisation is not a number anyone can act on, so the rules
    /// travel with the score rather than being remembered by whoever ran it.
    @Test("keeps the rules it measured under on the score")
    func carriesItsRules() {
        let loose = TextNormaliser(rules: [.caseFolding])
        let score = TranscriptionScorer.score("we are pinning", against: english, normaliser: loose)
        #expect(score.normalisation == [.caseFolding])
        #expect(TranscriptionScorer.score("x", against: english).normalisation == NormalisationRule.allCases)
    }

    @Test("keeps the timings it was given")
    func carriesTimings() {
        let score = TranscriptionScorer.score(
            english.romanised, against: english,
            stages: [.init(stage: .transcription, duration: .milliseconds(600), succeeded: true)])
        #expect(score.stages.count == 1)
        #expect(score.stages.first?.measurement.duration == .milliseconds(600))
        #expect(score.stages.first?.measurement.stage == .transcription)
        #expect(score.stages.first?.measurement.succeeded == true)
    }

    @Test("keeps the transcript, so a bad score can be read rather than guessed at")
    func keepsTheTranscript() {
        let score = TranscriptionScorer.score("what it actually said", against: english)
        #expect(score.transcript == "what it actually said")
        #expect(score.id == "sample-en")
    }
}
