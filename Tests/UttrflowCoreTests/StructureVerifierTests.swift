import Testing

@testable import UttrflowCore

@Suite("Structure verifier")
struct StructureVerifierTests {
    private static let pass: PassID = "structureVerifierTest"

    /// A draft of `parts`: a part starting with a newline or a bullet is a mark carrying the evidence given with it.
    private func draft(_ parts: [(String, BreakEvidence?)]) -> Draft {
        Draft(
            words: parts.map { part in
                var word = Draft.Word(text: part.0, heard: "", evidence: .unknown)
                if word.isLayoutMark { word.breakEvidence = part.1 }
                return word
            })
    }

    private func words(_ text: String) -> [(String, BreakEvidence?)] {
        text.split(separator: " ").map { (String($0), nil) }
    }

    private func verify(
        _ parts: [(String, BreakEvidence?)], per100: Int = 10
    ) -> (text: String, removed: [StructureVerifier.Reason]) {
        let result = StructureVerifier.verified(draft(parts), breaksPer100Words: per100, by: Self.pass)
        return (result.draft.text, result.removed.map(\.reason))
    }

    private let pause = BreakEvidence.longPause(.seconds(2))

    @Test("takes out a break that nothing recorded a reason for, and no word")
    func untaggedBreak() {
        let result = verify(words("We shipped it.") + [("\n\n", nil)] + words("Billing is next."))
        #expect(result.text == "We shipped it. Billing is next.")
        #expect(result.removed == [.untagged])
    }

    @Test("keeps a break after a complete sentence")
    func completeSentence() {
        let result = verify(words("We shipped it.") + [("\n\n", pause)] + words("Billing is next."))
        #expect(result.text == "We shipped it.\n\nBilling is next.")
        #expect(result.removed.isEmpty)
    }

    @Test("takes out an inferred break after a word that leads on, or after a comma")
    func incompleteSentence() {
        #expect(
            verify(words("We shipped it and") + [("\n\n", pause)] + words("Billing is next.")).removed
                == [.incompleteSentence])
        #expect(
            verify(words("We shipped it,") + [("\n\n", .topicCue)] + words("billing is next.")).removed
                == [.incompleteSentence])
    }

    @Test("keeps a break the speaker asked for after a word that leads on")
    func spokenBreakIsNotJudged() {
        let result = verify(words("We shipped it and") + [("\n", .spokenCommand)] + words("Billing is next."))
        #expect(result.removed.isEmpty)
        #expect(result.text == "We shipped it and\nBilling is next.")
    }

    @Test("keeps a break a piece already carried, after a comma, as it keeps one the speaker asked for")
    func carriedBreakIsNotJudged() {
        let result = verify(words("Thanks for your patience,") + [("\n", .carried)] + words("Dana."))
        #expect(result.removed.isEmpty)
        #expect(result.text == "Thanks for your patience,\nDana.")
    }

    @Test("takes out an inferred break inside a bracket or a quotation")
    func insideSpan() {
        #expect(
            verify(words("He said (we shipped it.") + [("\n\n", pause)] + words("Billing is next.)")).removed
                == [.insideSpan])
        #expect(
            verify(words("She wrote \"we shipped it.") + [("\n\n", pause)] + words("Billing is next.\""))
                .removed
                == [.insideSpan])
    }

    @Test("takes out an inferred break between the digits of one number")
    func insideNumber() {
        #expect(
            verify(words("It costs 12") + [("\n\n", pause)] + words("50 dollars.")).removed == [.insideNumber]
        )
    }

    @Test("takes out an inferred break between two parts of an address")
    func insideAddress() {
        let result = verify(
            words("Open https://example.com/a") + [("\n\n", pause)] + words("https://example.org/b now."))
        #expect(result.removed == [.insideAddress])
    }

    @Test("takes out an inferred list of one item, or with an item that is not a clause")
    func inferredListShape() {
        let lone = verify(
            words("Do this") + [("\n- ", .ordinalEnumeration)] + words("Finish the onboarding flow"))
        #expect(lone.removed == [.loneList])
        #expect(lone.text == "Do this Finish the onboarding flow")
        let thin =
            verify(
                [("\n- ", .ordinalEnumeration)] + words("Finish the onboarding flow")
                    + [("\n- ", .ordinalEnumeration)] + words("Milk"))
        #expect(thin.removed == [.itemNotClause, .itemNotClause])
    }

    @Test("keeps an inferred list of two clauses, and a lone list the speaker asked for")
    func legalLists() {
        let two = verify(
            [("\n- ", .ordinalEnumeration)] + words("Finish the onboarding flow")
                + [("\n- ", .ordinalEnumeration)] + words("Fix the login screen"))
        #expect(two.removed.isEmpty)
        let asked = verify(words("Buy") + [("\n- ", .spokenCommand)] + words("milk"))
        #expect(asked.removed.isEmpty)
    }

    @Test("takes the weakest inferred breaks out of a text over its budget, shortest pause first")
    func budget() {
        var parts: [(String, BreakEvidence?)] = []
        let pauses: [Double] = [2, 5, 3]
        for pause in pauses {
            parts += Array(repeating: ("Done.", nil), count: 5)
            parts.append(("\n\n", .longPause(.seconds(pause))))
        }
        parts += Array(repeating: ("Done.", nil), count: 5)
        // Twenty words at ten breaks per hundred allow two.
        let result = verify(parts, per100: 10)
        #expect(result.removed == [.overBudget])
        #expect(result.text.components(separatedBy: "\n\n").count == 3)
        // The shortest pause went: the first break, after the fifth word.
        #expect(result.text.hasPrefix("Done. Done. Done. Done. Done. Done."))
    }

    @Test("lets a break the speaker asked for stand over the budget")
    func spokenBreaksAreNotCounted() {
        var parts: [(String, BreakEvidence?)] = []
        for _ in 0..<4 {
            parts += [("Done.", nil), ("\n\n", .spokenCommand)]
        }
        parts.append(("Done.", nil))
        #expect(verify(parts, per100: 10).removed.isEmpty)
    }

    @Test("finds nothing more to take out of what it already verified")
    func idempotent() {
        let parts =
            words("We shipped it and") + [("\n\n", pause)] + words("Billing is next.")
            + [("\n\n", nil)] + words("Done.")
        let once = StructureVerifier.verified(draft(parts), breaksPer100Words: 10, by: Self.pass)
        let twice = StructureVerifier.verified(once.draft, breaksPer100Words: 10, by: Self.pass)
        #expect(twice.removed.isEmpty)
        #expect(twice.draft.text == once.draft.text)
    }
}
