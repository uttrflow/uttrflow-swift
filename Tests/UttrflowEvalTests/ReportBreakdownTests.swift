import Foundation
import Testing

@testable import UttrflowEval

/// Builds scores directly, since what is tested is arithmetic over a thousand results.
func score(
    _ id: String,
    language: TranscriptionCase.Language = .english,
    stressor: TranscriptionCase.Stressor = .everyday,
    stresses: [String] = [],
    cohort: String? = nil,
    reference: [String],
    heard: [String],
    lost: [String] = [],
    answeredIn: Script = .latin,
    failure: TranscriptionFailure? = nil
) -> PassageScore {
    PassageScore(
        caseID: id, language: language, stressor: stressor,
        wordErrorRate: failure?.isScorable == false
            ? nil : .measure(reference: reference, hypothesis: heard),
        answeredIn: answeredIn, scoredAgainst: .latin, lost: lost, failure: failure,
        stresses: stresses, cohortID: cohort)
}

@Suite("Reading a thousand results")
struct ReportBreakdownTests {
    private func report(_ scores: [PassageScore]) -> TranscriptionReport {
        TranscriptionReport(label: "test", scores: scores)
    }

    /// At a thousand samples the eye-catching rate is nearly always the row with forty words behind it.
    @Test("reports by language, and says how much each row rests on")
    func byLanguage() {
        let subject = report([
            score(
                "a", language: .english, reference: ["one", "two", "three", "four"],
                heard: ["one", "two", "three", "four"]),
            score("b", language: .hindi, reference: ["ek", "do"], heard: ["ek", "teen"]),
            score("c", language: .hinglish, reference: ["ek", "two"], heard: ["ek", "two"]),
        ])
        #expect(subject.byLanguage.map(\.label) == ["english", "hindi", "hinglish"])
        #expect(subject.byLanguage[1].rate.rate == 0.5)
        #expect(subject.byLanguage[1].referenceWordCount == 2)
        #expect(subject.byLanguage[1].passages == 1)
        #expect(subject.byLanguage[0].id == "english")
    }

    /// The question worth answering is "how are we on proper nouns", so the rows overlap.
    @Test("a sample stressing two things is counted under both")
    func byStress() {
        let subject = report([
            score(
                "a", stresses: ["accent", "punctuation"], reference: ["one", "two"], heard: ["one", "x"]),
            score("b", stresses: ["punctuation"], reference: ["one", "two"], heard: ["one", "two"]),
        ])
        #expect(subject.byStress.map(\.label) == ["accent", "punctuation"])
        #expect(subject.byStress[0].passages == 1)
        #expect(subject.byStress[1].passages == 2)
        // Four words in the punctuation row, two in the accent row: they overlap and do not sum to four.
        #expect(subject.byStress[1].referenceWordCount == 4)
        #expect(subject.wordErrorRate(stressing: "accent")?.rate == 0.5)
        #expect(subject.wordErrorRate(stressing: "nothing-like-this") == nil)
    }

    /// A pooled figure hides one speaker's regression behind another's improvement.
    @Test("reports by cohort, with the unattributed recordings as their own row")
    func byCohort() {
        let subject = report([
            score("a", cohort: "naveen-quiet", reference: ["one", "two"], heard: ["one", "two"]),
            score("b", cohort: "priya-cafe", reference: ["one", "two"], heard: ["x", "y"]),
            score("c", reference: ["one", "two"], heard: ["one", "two"]),
        ])
        #expect(subject.byCohort.map(\.label) == ["naveen-quiet", "priya-cafe", "unattributed"])
        #expect(subject.byCohort[1].rate.rate == 1)
        #expect(subject.byCohort[2].rate.rate == 0)
    }

    @Test("an empty run has no rows at all, rather than rows of zero")
    func emptyRun() {
        let subject = report([])
        #expect(subject.byLanguage.isEmpty)
        #expect(subject.byStress.isEmpty)
        #expect(subject.byCohort.isEmpty)
        #expect(subject.findings.isEmpty)
    }

    // MARK: Findings

    /// The whole answer to "eighteen results can be a list; a thousand cannot".
    @Test("the same mistake across forty samples is one finding")
    func groupsRecurringMistakes() {
        let scores = (1...40).map { index in
            score(
                "s\(index)", reference: ["send", "it", "to", "priya"], heard: ["send", "it", "to", "preeya"])
        }
        let findings = report(scores).findings
        #expect(findings.count == 1)
        #expect(findings.first?.signature == .misheard("priya", heard: "preeya"))
        #expect(findings.first?.occurrences == 40)
        #expect(findings.first?.sampleCount == 40)
        #expect(findings.first?.samples.first == "s1")
    }

    @Test("ranks findings by what they actually cost")
    func ranksFindings() {
        let subject = report([
            score("a", reference: ["priya", "one"], heard: ["preeya", "one"]),
            score("b", reference: ["priya", "two"], heard: ["preeya", "too"]),
            score("c", reference: ["priya"], heard: ["preeya"]),
        ])
        let findings = subject.findings
        #expect(findings.first?.signature == .misheard("priya", heard: "preeya"))
        #expect(findings.first?.occurrences == 3)
        #expect(findings.count == 2)
    }

    @Test("counts every kind of failure, not only misheard words")
    func everyKindOfFinding() {
        let subject = report([
            score("a", reference: ["one", "two"], heard: ["one"], lost: ["two"]),
            score("b", reference: ["one"], heard: ["one", "extra"]),
            score("c", reference: ["one"], heard: ["एक"], answeredIn: .devanagari),
            score("d", reference: [], heard: [], failure: .audioUnreadable("no file")),
            score("e", reference: ["one"], heard: [], failure: .recognisedNothing),
        ])
        let signatures = Set(subject.findings.map(\.signature))
        #expect(signatures.contains(.dropped("two")))
        #expect(signatures.contains(.inserted("extra")))
        #expect(signatures.contains(.lostRequiredTerm("two")))
        #expect(signatures.contains(.answeredInDevanagari))
        #expect(signatures.contains(.failed(.audioUnreadable)))
        #expect(signatures.contains(.failed(.recognisedNothing)))
    }

    @Test("every finding can be read as a sentence")
    func findingsExplainThemselves() {
        let all: [Finding.Signature] = [
            .misheard("priya", heard: "preeya"), .dropped("the"), .inserted("um"),
            .lostRequiredTerm("PostgreSQL"), .answeredInDevanagari, .failed(.engineFailed),
        ]
        for signature in all { #expect(signature.description.count > 5) }
        #expect(Finding.Signature.misheard("a", heard: "b").description == "\"a\" heard as \"b\"")
    }

    /// A report that prints everything is unread; one that silently truncates is untrusted.
    @Test("shows the worst findings and counts what it left out")
    func capsFindings() {
        let scores = (1...30).map { index in
            score("s\(index)", reference: ["word\(index)"], heard: ["heard\(index)"])
        }
        let (shown, hiddenOccurrences, hidden) = report(scores).topFindings(10)
        #expect(shown.count == 10)
        #expect(hidden == 20)
        #expect(hiddenOccurrences == 20)

        let everything = report(scores).topFindings(100)
        #expect(everything.shown.count == 30)
        #expect(everything.hidden == 0)
    }

    /// `--summarise` reads banked results, so a decoder refusing an older file would force a re-measure.
    @Test("a result banked before these fields existed still summarises")
    func decodesAnOlderResult() throws {
        let older = """
            {"caseID":"en-standup","language":"english","stressor":"everyday",
             "answeredIn":"latin","scoredAgainst":"latin"}
            """
        let stored = try JSONDecoder().decode(PassageScore.self, from: Data(older.utf8))
        #expect(stored.stresses == ["everyday"], "derived from the typed axis it did have")
        #expect(stored.cohortID == nil)
        #expect(stored.lost.isEmpty)
        #expect(stored.transcript.isEmpty)
        #expect(stored.stages.isEmpty)
        #expect(stored.normalisation.isEmpty)
        #expect(stored.wordErrorRate == nil)
        // And the report built from it still groups, which is the point of decoding it.
        #expect(report([stored]).byLanguage.isEmpty, "an unscorable result has no rate to slice")
    }

    @Test("a round trip keeps everything a report reads")
    func roundTripsAFullResult() throws {
        let original = score(
            "a", language: .hinglish, stresses: ["code-switching"], cohort: "naveen-quiet",
            reference: ["one"], heard: ["two"], lost: ["one"])
        let encoded = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(PassageScore.self, from: encoded) == original)
    }

    @Test("one passage hitting the same mistake twice is one sample, twice over")
    func countsOccurrencesAndSamplesSeparately() {
        let subject = report([
            score("a", reference: ["priya", "and", "priya"], heard: ["preeya", "and", "preeya"])
        ])
        #expect(subject.findings.first?.occurrences == 2)
        #expect(subject.findings.first?.sampleCount == 1)
    }
}
