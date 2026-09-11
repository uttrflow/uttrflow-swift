import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Pins issue #218: the doubtful-run checks read the position the run stands at, not the whole text.
@Suite("Issue218")
struct Issue218RegressionTests {
    private let sut = MeaningPreservationGuard()

    private func draft(_ text: String) -> Draft {
        Draft(words: text.split(separator: " ").map { Draft.Word(String($0)) }, confidencesAreReal: true)
    }

    @Test("an offered candidate standing elsewhere no longer passes a substitution that was never offered")
    func candidateElsewhere() {
        let offered = [DoubtfulSpan(heard: "money", confidence: 0.31, candidates: ["main"])]
        let verdict = sut.verdict(
            draft: draft("the main thing is money"), rewritten: "The main thing is mine.",
            offering: offered)
        #expect(!verdict.isAccepted, "'mine' was never offered as a reading of 'money'")
    }

    @Test("the heard run standing elsewhere no longer passes a substitution that was never offered")
    func heardElsewhere() {
        let offered = [DoubtfulSpan(heard: "mark", confidence: 0.31, candidates: ["Mark"])]
        let verdict = sut.verdict(
            draft: draft("call mark before mark leaves"), rewritten: "Call Mark before Mike leaves.",
            offering: offered)
        #expect(!verdict.isAccepted, "'Mike' was never offered as a reading of 'mark'")
    }

    @Test("the reading check reads what stands at the doubtful run, not what stands anywhere")
    func readingIsJudgedWhereItStands() {
        #expect(
            !MeaningPreservationGuard.candidateVerdict(
                [DoubtfulSpan(heard: "money", confidence: 0.31, candidates: ["main"])],
                kept: "the main thing is money", rewritten: "The main thing is mine."
            ).isAccepted, "the earlier clause's 'main' says nothing about what replaced 'money'")
    }

    @Test("offering a reading no longer excuses the doubtful word from the survival check")
    func offeringExcusesOnlyWhatWasWritten() {
        let offered = [DoubtfulSpan(heard: "money", confidence: 0.31, candidates: ["main"])]
        #expect(
            !MeaningPreservationGuard.grammarVerdict(
                kept: "the main thing is money", rewritten: "The main thing is mine.",
                allowing: offered
            ).isAccepted, "'money' was replaced by a word nobody offered, so it did not survive")
        #expect(
            !MeaningPreservationGuard.grammarVerdict(
                kept: "the main thing is money", rewritten: "The main thing is mine."
            ).isAccepted, "with no span offered the same rewrite is refused")
    }

    /// The rewrite keeps "ice" and rewrites only "cream", so the changed run is a part of the doubtful run.
    @Test("a doubtful run the rewrite only partly changed is still judged where it stands")
    func aPartlyChangedRunIsStillJudged() {
        let offered = [DoubtfulSpan(heard: "ice cream", confidence: 0.31, candidates: ["I scream"])]
        let verdict = sut.verdict(
            draft: draft("the ice cream is cold"), rewritten: "The ice screams is cold.",
            offering: offered)
        #expect(verdict == .rejected(reason: "the rewrite read 'ice cream' as a word it was not offered"))
    }

    @Test("the same partly changed run is refused through the two-text form as well")
    func aPartlyChangedRunIsJudgedOverTwoTexts() {
        #expect(
            !MeaningPreservationGuard.candidateVerdict(
                [DoubtfulSpan(heard: "ice cream", confidence: 0.31, candidates: ["I scream"])],
                kept: "the ice cream is cold", rewritten: "The ice screams is cold."
            ).isAccepted, "'ice screams' was never offered as a reading of 'ice cream'")
    }

    @Test("a multi-word run written as the reading it was offered is still accepted")
    func aMultiWordReadingStillStands() {
        let offered = [DoubtfulSpan(heard: "ice cream", confidence: 0.31, candidates: ["I scream"])]
        #expect(
            sut.verdict(
                draft: draft("the ice cream is cold"), rewritten: "The I scream is cold.",
                offering: offered
            ).isAccepted)
    }

    @Test("a multi-word run left as it was heard is still accepted")
    func aMultiWordRunLeftAloneStillStands() {
        let offered = [DoubtfulSpan(heard: "ice cream", confidence: 0.31, candidates: ["I scream"])]
        #expect(
            sut.verdict(
                draft: draft("the ice cream is cold"), rewritten: "The ice cream is cold.",
                offering: offered
            ).isAccepted)
    }

    @Test("a reading written where it was offered is still accepted")
    func theOfferedReadingStillStands() {
        let offered = [DoubtfulSpan(heard: "money", confidence: 0.31, candidates: ["main"])]
        #expect(
            sut.verdict(
                draft: draft("the only thing is money"), rewritten: "The only thing is main.",
                offering: offered
            ).isAccepted)
    }
}
