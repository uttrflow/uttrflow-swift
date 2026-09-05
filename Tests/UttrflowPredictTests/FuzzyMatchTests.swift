import Testing

@testable import UttrflowPredict

/// The query as the matcher wants it.
private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

/// Edits from one string to the nearest opening of another.
private func distance(_ query: String, _ candidate: String, within budget: Int = 3) -> Int {
    FuzzyMatch.prefixDistance(bytes(query), bytes(candidate), within: budget)
}

@Suite("Matching what was nearly typed")
struct FuzzyMatchTests {
    @Test("A transposition costs one edit, which is the whole reason for Damerau.")
    func transpositionIsOneEdit() {
        #expect(distance("gti c", "git commit -m") == 1)
        #expect(distance("docekr", "docker compose up") == 1)
        #expect(distance("kubctl", "kubectl describe") == 1)
    }

    @Test("An exact opening costs nothing.")
    func exactCostsNothing() {
        #expect(distance("git c", "git commit -m") == 0)
        #expect(distance("", "anything") == 0)
    }

    @Test("Distance is to the nearest opening, so the rest of a long candidate is free.")
    func lengthIsFree() {
        #expect(distance("git", "git commit --amend --no-edit --verbose") == 0)
    }

    @Test("A candidate shorter than the query still costs the missing characters.")
    func shortCandidate() {
        #expect(distance("git commit", "git", within: 9) == 7)
        #expect(distance("abc", "") == 3)
    }

    @Test("A distance past the budget is reported as past the budget, not measured exactly.")
    func budgetCapsTheAnswer() {
        #expect(distance("zzzzz", "git commit", within: 1) == 2)
    }

    @Test(
        "Two different commands sharing an opening are one substitution apart, which is why fuzzy is a fallback."
    )
    func neighboursAreClose() {
        #expect(distance("git p", "git commit") == 1)
    }

    @Test("The budget grows with the query, so two letters cannot match the whole corpus.")
    func budgetGrowsWithLength() {
        #expect(FuzzyMatch.budget(forQueryOfLength: 0) == 0)
        #expect(FuzzyMatch.budget(forQueryOfLength: 2) == 0)
        #expect(FuzzyMatch.budget(forQueryOfLength: 3) == 1)
        #expect(FuzzyMatch.budget(forQueryOfLength: 5) == 1)
        #expect(FuzzyMatch.budget(forQueryOfLength: 6) == 2)
        #expect(FuzzyMatch.budget(forQueryOfLength: 40) == 2)
    }
}

@Suite("Rejecting candidates cheaply")
struct MaskTests {
    @Test("The mask ignores case, so a capital letter is not a missing one.")
    func caseInsensitive() {
        #expect(FuzzyMatch.mask(bytes("GIT")) == FuzzyMatch.mask(bytes("git")))
    }

    @Test("A candidate holding every character typed is never rejected.")
    func keepsRealMatches() {
        let query = FuzzyMatch.mask(bytes("gti c"))
        let candidate = FuzzyMatch.mask(bytes("git co"))
        #expect(FuzzyMatch.couldMatch(query: query, candidate: candidate, within: 1))
    }

    @Test("A candidate missing more characters than the budget allows is rejected.")
    func rejectsHopelessOnes() {
        let query = FuzzyMatch.mask(bytes("xyzw"))
        let candidate = FuzzyMatch.mask(bytes("git c"))
        #expect(!FuzzyMatch.couldMatch(query: query, candidate: candidate, within: 1))
    }

    @Test("The mask window is the query plus its budget, never narrower, or a true match could be lost.")
    func windowCoversTheComparison() {
        #expect(FuzzyMatch.maskWidth(forQueryOfLength: 5, within: 1) == 6)
        #expect(FuzzyMatch.maskWidth(forQueryOfLength: 3, within: 0) == 3)
    }

    @Test("Rejecting never discards a candidate the full comparison would have kept.")
    func filterIsSound() {
        let corpus = [
            "git commit -m", "git checkout beta", "docker compose up", "npm run dev",
            "make verify", "kubectl describe pod", "swift build", "brew upgrade",
        ]
        for query in ["gti c", "git c", "docekr", "mkae", "npm r", "swfit"] {
            let needle = bytes(query)
            let budget = FuzzyMatch.budget(forQueryOfLength: needle.count)
            let width = FuzzyMatch.maskWidth(forQueryOfLength: needle.count, within: budget)
            let queryMask = FuzzyMatch.mask(needle)
            for text in corpus {
                let candidate = bytes(text)
                let matches = FuzzyMatch.prefixDistance(needle, candidate, within: budget) <= budget
                let survives = FuzzyMatch.couldMatch(
                    query: queryMask, candidate: FuzzyMatch.mask(candidate.prefix(width)),
                    within: budget)
                #expect(!matches || survives, "\(query) against \(text) was wrongly rejected")
            }
        }
    }

    @Test("A prefix is recognised without measuring any distance at all.")
    func prefixIsCheap() {
        #expect(FuzzyMatch.isPrefix(bytes("git"), of: bytes("git commit")))
        #expect(!FuzzyMatch.isPrefix(bytes("gti"), of: bytes("git commit")))
        #expect(!FuzzyMatch.isPrefix(bytes("git commit"), of: bytes("git")))
    }
}
