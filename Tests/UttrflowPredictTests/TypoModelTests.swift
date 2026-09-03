import Foundation
import Testing

@testable import UttrflowPredict

/// How likely it is that somebody meaning the second string typed the first.
private func chance(_ typed: String, meaning meant: String) -> Double {
    TypoModel.likelihood(typed: typed, meant: meant)
}

@Suite("How a word gets mistyped")
struct TypoModelTests {
    @Test("Typing exactly what was meant is certain.")
    func exactIsCertain() {
        #expect(chance("git", meaning: "git") == 1)
        #expect(chance("", meaning: "") == 1)
    }

    @Test("Every likelihood is a probability, so it sits between zero and one.")
    func staysAProbability() {
        for (typed, meant) in [("gti", "git"), ("qqqq", "git"), ("", "git"), ("git", "")] {
            let value = chance(typed, meaning: meant)
            #expect(value > 0)
            #expect(value <= 1)
        }
    }

    @Test("A transposition of neighbouring characters beats a substitution by a distant key.")
    func transpositionBeatsDistantSubstitution() {
        #expect(chance("gti", meaning: "git") > chance("gxi", meaning: "git"))
    }

    @Test("A transposition is the cheapest slip of all, so it beats even a neighbouring key.")
    func transpositionIsCheapest() {
        #expect(chance("gti", meaning: "git") > chance("gut", meaning: "git"))
    }

    @Test("Hitting a key next to the intended one beats hitting one across the keyboard.")
    func adjacentBeatsDistant() {
        #expect(chance("cst", meaning: "cat") > chance("cpt", meaning: "cat"))
    }

    @Test("Doubling a letter beats typing a stray unrelated one.")
    func doublingBeatsStray() {
        #expect(chance("gitt", meaning: "git") > chance("gitx", meaning: "git"))
    }

    @Test("Dropping one of a doubled pair beats dropping a letter that stood alone.")
    func droppedRepeatBeatsDroppedLetter() {
        #expect(chance("comit", meaning: "commit") > chance("commt", meaning: "commit"))
    }

    @Test("Dropping the first of a doubled pair costs the same as dropping the second.")
    func eitherHalfOfAPairCostsTheSame() {
        #expect(TypoModel.deletion(Array("commit"), at: 3) == TypoModel.deletion(Array("commit"), at: 4))
    }

    @Test("A substitution in the first character is likelier to have been meant than the same one later.")
    func firstCharacterSubstitutionIsRarer() {
        #expect(chance("gaf", meaning: "gag") > chance("fag", meaning: "gag"))
    }

    @Test("A transposition in the first characters is likelier to have been meant than the same one later.")
    func firstCharacterTranspositionIsRarer() {
        #expect(chance("gti", meaning: "git") > chance("igt", meaning: "git"))
    }

    @Test("A dropped first character is likelier to have been meant than a dropped middle one.")
    func firstCharacterDeletionIsRarer() {
        #expect(chance("gt", meaning: "git") > chance("it", meaning: "git"))
    }

    @Test("A stray first character is likelier to have been meant than a stray middle one.")
    func firstCharacterInsertionIsRarer() {
        #expect(chance("gixt", meaning: "git") > chance("xgit", meaning: "git"))
    }

    @Test("The more slips a spelling needs, the less likely it is.")
    func moreSlipsAreLessLikely() {
        let one = chance("gut", meaning: "git")
        let two = chance("gyy", meaning: "git")
        #expect(chance("git", meaning: "git") > one)
        #expect(one > two)
    }

    @Test("Case is not a typing slip, so it costs nothing.")
    func caseIsFree() {
        #expect(chance("Git", meaning: "git") == 1)
    }

    @Test("The log likelihood is the log of the likelihood, and never rises above zero.")
    func logsAgreeWithProbabilities() {
        let log = TypoModel.logLikelihood(typed: "gti", meant: "git")
        #expect(log < 0)
        #expect(abs(exp(log) - chance("gti", meaning: "git")) < 1e-12)
        #expect(TypoModel.logLikelihood(typed: "git", meant: "git") == 0)
    }

    @Test("The costs rank the slips from commonest to rarest.")
    func costsAreOrdered() {
        #expect(TypoModel.transpositionCost < TypoModel.repeatedLetterCost)
        #expect(TypoModel.repeatedLetterCost < TypoModel.adjacentSubstitutionCost)
        #expect(TypoModel.adjacentSubstitutionCost < TypoModel.indelCost)
        #expect(TypoModel.indelCost < TypoModel.distantSubstitutionCost)
        #expect(TypoModel.firstCharacterMultiplier > 1)
    }

    @Test("A slip at the start costs more than the same slip anywhere else.")
    func weightingIsOnlyForTheStart() {
        #expect(TypoModel.weighted(1, atStart: true) == TypoModel.firstCharacterMultiplier)
        #expect(TypoModel.weighted(1, atStart: false) == 1)
    }

    @Test("Adjacency is symmetric, so no key claims a neighbour that does not claim it back.")
    func adjacencyIsSymmetric() {
        for (key, neighbours) in TypoModel.neighbours {
            for neighbour in neighbours {
                #expect(TypoModel.areAdjacent(neighbour, key), "\(neighbour) does not claim \(key)")
            }
        }
    }

    @Test("Every letter of the alphabet has neighbours, and no key is its own.")
    func adjacencyCoversTheAlphabet() {
        #expect(TypoModel.neighbours.count == 26)
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            #expect(TypoModel.neighbours[letter]?.isEmpty == false)
            #expect(TypoModel.areAdjacent(letter, letter) == false)
        }
    }

    @Test("A character the keyboard table does not carry is adjacent to nothing.")
    func unknownKeysAreNeverAdjacent() {
        #expect(TypoModel.areAdjacent("-", "_") == false)
        #expect(chance("g-t", meaning: "g_t") < chance("gut", meaning: "git"))
    }

    @Test("A candidate sharing nothing with what was typed is far likelier to be a different word.")
    func unrelatedTextIsImplausible() {
        #expect(chance("git", meaning: "npm") < 1e-4)
    }
}
