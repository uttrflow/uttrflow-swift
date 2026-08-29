import Testing

@testable import UttrflowCore

/// I8 — a soft cap with a warning before it is hit, not a silent truncation after. Those
/// are two different products, and these tests are mostly about which one this is.
@Suite("I8 · how long a dictation may run")
struct DictationLimitTests {
    static let limit = DictationLimit(warnAfter: .seconds(180), stopAfter: .seconds(240))

    @Test("an ordinary dictation is left alone")
    func ordinary() {
        #expect(Self.limit.advice(at: .seconds(0)) == .keepGoing)
        #expect(Self.limit.advice(at: .seconds(30)) == .keepGoing)
        #expect(Self.limit.advice(at: .seconds(179)) == .keepGoing)
    }

    /// The warning is the feature. A cut with no warning tells the user afterwards, which
    /// is the worst moment to find out.
    @Test("the warning comes before the cap, and says how long is left")
    func warnsBefore() {
        #expect(Self.limit.advice(at: .seconds(180)) == .approaching(remaining: .seconds(60)))
        #expect(Self.limit.advice(at: .seconds(210)) == .approaching(remaining: .seconds(30)))
    }

    @Test("and there is real time between the warning and the end")
    func roomToFinish() {
        #expect(Self.limit.warnAfter < Self.limit.stopAfter)
        #expect(DictationLimit.default.stopAfter - DictationLimit.default.warnAfter >= .seconds(30))
    }

    @Test("at the cap, the dictation finishes")
    func finishes() {
        #expect(Self.limit.advice(at: .seconds(240)) == .finishNow)
        #expect(Self.limit.advice(at: .seconds(600)) == .finishNow)
    }

    /// "Soft" is the whole word. Finishing transcribes what was said; a cap that discarded
    /// the audio would be worse than no cap, since the reason for one is memory and
    /// transcription time — both served by stopping and keeping.
    @Test("there is no advice that throws the dictation away")
    func nothingIsDiscarded() {
        for seconds in [0, 179, 180, 239, 240, 1_000] {
            let advice = Self.limit.advice(at: .seconds(seconds))
            #expect(advice == .keepGoing || advice == .finishNow || isApproaching(advice))
        }
    }

    private func isApproaching(_ advice: DictationAdvice) -> Bool {
        if case .approaching = advice { return true }
        return false
    }

    /// Speech is about 150 words a minute, so the shipped cap is roughly six hundred words
    /// — past any message or paragraph somebody dictates, and about where a single
    /// utterance is a microphone left running.
    @Test("the shipped cap is long enough to be about a mistake, not a long sentence")
    func theDefaultIsGenerous() {
        #expect(DictationLimit.default.warnAfter >= .seconds(120))
        #expect(DictationLimit.default.stopAfter >= .seconds(180))
    }
}
