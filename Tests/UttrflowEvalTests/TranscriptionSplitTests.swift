// Tests that the transcription corpus split is complete, leak-free and thick enough to judge each language.
import Testing

@testable import UttrflowEval

@Suite("Transcription split")
struct TranscriptionSplitTests {
    @Test("the committed split has no findings")
    func committedSplitIsSound() {
        let findings = SplitLeakAudit().findings
        #expect(findings.isEmpty, "\(findings)")
    }

    @Test("each language has two passages on every side", arguments: TranscriptionCase.Language.allCases)
    func countsPerLanguage(language: TranscriptionCase.Language) {
        #expect(SplitLeakAudit().counts(in: language) == [.fit: 2, .calibration: 2, .test: 2])
    }

    @Test("moving a test passage to fit leaves a language short of test passages")
    func movingAPassageFails() {
        var assignment = TranscriptionSplit.assignment
        assignment["en-people"] = .fit
        let findings = SplitLeakAudit(assignment: assignment).findings
        #expect(findings == [.tooFewTestPassages(language: .english, count: 1)])
    }

    @Test("a passage repeated on another side is named as a shared run")
    func copiedPassageIsFound() throws {
        let test = try #require(TranscriptionCorpus.passage("en-people"))
        let copy = TranscriptionCase(
            id: "en-copy", language: .english, stressor: .everyday, romanised: test.romanised)
        var assignment = TranscriptionSplit.assignment
        assignment["en-copy"] = .calibration
        let findings = SplitLeakAudit(passages: TranscriptionCorpus.all + [copy], assignment: assignment)
            .findings
        #expect(!findings.isEmpty)
        #expect(
            findings.allSatisfy {
                if case .sharedRun("en-copy", .calibration, "en-people", _) = $0 { true } else { false }
            })
    }

    @Test("an unassigned passage and a stale assignment are both named")
    func assignmentMatchesCorpus() {
        var assignment = TranscriptionSplit.assignment
        assignment["en-standup"] = nil
        assignment["en-gone"] = .fit
        let findings = SplitLeakAudit(assignment: assignment).findings
        #expect(findings == [.unassigned(passageID: "en-standup"), .staleAssignment(passageID: "en-gone")])
    }
}
