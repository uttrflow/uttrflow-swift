import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// A rewrite that writes the kept words in their order is judged only by the checks that read marks, case and layout.
@Suite("SameWordsProof")
struct SameWordsProofTests {
    private let sut = MeaningPreservationGuard()

    @Test(
        "marks at a word's edges, case and layout leave the words the same",
        arguments: [
            ("send the report to the team on friday", "Send the report to the team, on Friday."),
            ("hi sam thanks", "Hi Sam,\n\nThanks!"),
            ("bring a jacket it gets cold", "Bring a jacket (it gets cold)."),
            ("he said ship it", "He said: \"Ship it.\""),
            ("first point second point", "- First point\n- Second point"),
        ])
    func marksAndCase(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.sameWords(kept, rewritten))
    }

    @Test(
        "a mark inside a word is part of it, so moving or dropping it changes the word",
        arguments: [
            ("it's late", "its late"),
            ("don't go", "don t go"),
            ("version 3.5", "version 3, 5"),
            ("a well-known name", "a well known name"),
            ("send an e-mail", "send an email"),
        ])
    func innerMarks(kept: String, rewritten: String) {
        #expect(!MeaningPreservationGuard.sameWords(kept, rewritten))
    }

    @Test(
        "a changed, dropped, added or moved word is never the same words",
        arguments: [
            "Send the report to the team on Monday.",
            "Send the report to the team.",
            "Send the report to the whole team on Friday.",
            "Send the team the report on Friday.",
            "Send the reports to the team on Friday.",
        ])
    func changedWords(rewritten: String) {
        #expect(!MeaningPreservationGuard.sameWords("send the report to the team on friday", rewritten))
    }

    @Test("the words answer only for the checks that read which words stand where")
    func provenChecks() {
        let proven = MeaningPreservationGuard.checks.filter {
            if case .proven = $0.sameWords { true } else { false }
        }
        let narrowed = MeaningPreservationGuard.checks.filter {
            if case .narrowed = $0.sameWords { true } else { false }
        }
        #expect(proven.map(\.name) == ["length", "readings", "confidentHomophone"])
        #expect(narrowed.map(\.name) == ["grammar"])
    }

    @Test("a sentence end between two words the word checks read as one is accepted")
    func sentenceEndBetweenJoinedWords() {
        let draft = Draft(text: "ask if we can not everyone agrees")
        #expect(sut.verdict(draft: draft, rewritten: "Ask if we can. Not everyone agrees.") == .accepted)
    }

    @Test("a lowered name is refused though the words are the same")
    func loweredName() {
        let draft = Draft(text: "send it to Mark before noon")
        let verdict = sut.verdict(draft: draft, rewritten: "Send it to mark before noon.")
        #expect(
            verdict == .rejected(reason: "the rewrite changed the capitalization of 'Mark'", kind: .lostWord))
    }

    @Test("a long rewrite that ends no sentence is refused though the words are the same")
    func unpunctuated() {
        let spoken = Array(repeating: "we walked to the shop and then", count: 7).joined(separator: " ")
        let rewritten = spoken.replacingOccurrences(of: "then", with: "then,")
        #expect(MeaningPreservationGuard.sameWords(spoken, rewritten))
        guard case .rejected(_, let kind) = sut.verdict(draft: Draft(text: spoken), rewritten: rewritten)
        else {
            Issue.record("expected the unpunctuated rewrite to be refused")
            return
        }
        #expect(kind == .unpunctuated)
    }

    @Test(
        "a mark, a symbol or a break the words cannot see is still refused by its own check",
        arguments: [
            ("it costs $500", "It costs 500.", "numbers"),
            ("call john and mary", "Call John and Mary!", "symbols"),
            ("buy milk\nbuy bread", "Buy milk, buy bread.", "layout"),
        ])
    func keptChecks(kept: String, rewritten: String, check: String) {
        let input = GuardInput(draft: Draft(keepingLineBreaks: kept), rewritten: rewritten)
        #expect(input.sameWords)
        #expect(sut.checkResults(on: input).first { !$0.verdict.isAccepted }?.name == check)
    }

    @Test("a spoken mark the rewrite dropped is refused though the words are the same")
    func spokenMark() {
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown)
        let draft = pipeline.run(Draft(text: "bring a jacket open bracket it gets cold close bracket"))
        let input = GuardInput(draft: draft, rewritten: "Bring a jacket, it gets cold.")
        #expect(input.sameWords)
        #expect(sut.checkResults(on: input).first { !$0.verdict.isAccepted }?.name == "spokenPunctuation")
    }
}
