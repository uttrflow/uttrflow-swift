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
