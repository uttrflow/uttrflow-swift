import Testing

@testable import UttrflowPredict

/// How well a query abbreviates a candidate, as a number the tests can compare.
private func score(_ query: String, _ candidate: String) -> Double? {
    Abbreviation.score(query: query, candidate: candidate)
}

@Suite("Matching an abbreviation against what it stands for")
struct AbbreviationTests {
    @Test("Initials match the command they stand for, which is the whole point.")
    func initialsMatch() {
        #expect(score("gcm", "git commit -m") != nil)
        #expect(score("dcu", "docker compose up") != nil)
        #expect(score("kgp", "kubectl get pods") != nil)
    }

    @Test("A query that is not a subsequence does not match at all.")
    func absentLettersDoNotMatch() {
        #expect(score("gcx", "git commit -m") == nil)
        #expect(score("cg", "git commit") == nil)
        #expect(score("abc", "xbca") == nil)
    }

    @Test("An empty query abbreviates nothing, and nothing shorter than the query can hold it.")
    func degenerateInputsDoNotMatch() {
        #expect(score("", "git commit") == nil)
        #expect(score("", "") == nil)
        #expect(score("gcm", "gc") == nil)
    }

    @Test("Case is ignored in both directions, because an abbreviation is typed in a hurry.")
    func caseIsIgnored() {
        #expect(score("GCM", "git commit -m") != nil)
        #expect(score("gcm", "Git Commit -M") != nil)
    }

    @Test("An unbroken run outscores the same letters scattered through the candidate.")
    func consecutiveOutscoresScattered() throws {
        let run = try #require(score("abc", "abcdef"))
        let scattered = try #require(score("abc", "a1b2c3def"))
        #expect(run > scattered)
    }

    @Test("A letter starting a word outscores the same letter buried inside one.")
    func boundaryOutscoresMidWord() throws {
        let boundary = try #require(score("ac", "ab cd"))
        let midWord = try #require(score("ac", "abxcd"))
        #expect(boundary > midWord)
    }

    @Test("Hyphens, underscores and slashes start words as surely as a space does.")
    func everySeparatorStartsAWord() throws {
        let midWord = try #require(score("ac", "abxcd"))
        for candidate in ["ab-cd", "ab_cd", "ab/cd"] {
            let boundary = try #require(score("ac", candidate))
            #expect(boundary > midWord)
        }
    }

    @Test("A camelCase hump starts a word without a separator in front of it.")
    func camelHumpStartsAWord() throws {
        let hump = try #require(score("ac", "abCd"))
        let midWord = try #require(score("ac", "abcd"))
        #expect(hump > midWord)
    }

    @Test("A match at the very beginning outscores the same match found later.")
    func startOutscoresAnythingLater() throws {
        let atStart = try #require(score("cm", "commit"))
        let later = try #require(score("cm", "git commit"))
        #expect(atStart > later)
    }

    @Test("A long gap costs more than a short one, up to the point where it stops growing.")
    func gapsCostMoreTheLongerTheyAre() throws {
        let near = try #require(score("ab", "axb"))
        let far = try #require(score("ab", "axxxb"))
        #expect(near > far)
        let distant = try #require(score("ab", "a\(String(repeating: "x", count: 20))b"))
        #expect(distant > 0)
    }

    @Test("The best placement wins, so more candidate text never lowers the score.")
    func theBestPlacementWins() throws {
        let short = try #require(score("ab", "axb"))
        let longer = try #require(score("ab", "axb ab"))
        #expect(longer >= short)
    }

    @Test("Scores are comparable across candidates, so the better abbreviation ranks first.")
    func scoresRankCandidates() throws {
        let query = "gcm"
        let best = try #require(score(query, "git commit -m"))
        let worse = try #require(score(query, "gnome-calculator manual"))
        #expect(best > worse)
    }

    @Test("Only a short query with no spaces in it is worth a last-resort subsequence match.")
    func theGateIsNarrow() {
        #expect(Abbreviation.shouldAttempt(query: "gcm"))
        #expect(Abbreviation.shouldAttempt(query: "g"))
        #expect(Abbreviation.shouldAttempt(query: "gitcm"))
        #expect(!Abbreviation.shouldAttempt(query: ""))
        #expect(!Abbreviation.shouldAttempt(query: "gitcom"))
        #expect(!Abbreviation.shouldAttempt(query: "g c"))
        #expect(!Abbreviation.shouldAttempt(query: "g\tc"))
        #expect(!Abbreviation.shouldAttempt(query: " gc"))
    }

    @Test("The gate's limit is the length it says it is.")
    func theGateStopsWhereItSays() {
        let limit = Abbreviation.maximumQueryLength
        #expect(Abbreviation.shouldAttempt(query: String(repeating: "a", count: limit)))
        #expect(!Abbreviation.shouldAttempt(query: String(repeating: "a", count: limit + 1)))
    }
}
