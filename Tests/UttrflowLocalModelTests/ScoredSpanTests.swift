import Foundation
import Testing

@testable import UttrflowLocalModel

/// A vocabulary small enough to name every token: 0 bos, 1 "g", 2 "gi", 3 "git", 4 "gist", 5 " status", 6 "i", 7 " ", 8 "ls", 9 nothing, 10 "stat", 11 "us", 12 "sta", 13 "tu".
private let bytes: [[UInt8]] = [
    "<bos>", "g", "gi", "git", "gist", " status", "i", " ", "ls", "", "stat", "us", "sta", "tu",
].map {
    Array($0.utf8)
}

@Suite("Scoring a line whose typed opening ends inside a token")
struct ScoredSpanTests {
    @Test("A word cut inside a token owes its typed remainder to the first judged token.")
    func aCutWordIsOwed() {
        let span = ScoredSpan(whole: [0, 3, 5], typed: [0, 1, 6], bytes: bytes)
        #expect(span == ScoredSpan(start: 1, owed: Array("gi".utf8)))
    }

    @Test(
        "A line token that writes only typed bytes was typed, so judging starts past it and the rest is owed."
    )
    func aTypedTokenIsPassedOver() {
        let span = ScoredSpan(whole: [0, 10, 11, 5], typed: [0, 12, 13], bytes: bytes)
        #expect(span == ScoredSpan(start: 2, owed: Array("u".utf8)))
    }

    @Test("A typed opening wholly spelt by line tokens leaves nothing owed to the token after them.")
    func typedTokensSpeltDifferentlyAreConsumed() {
        let span = ScoredSpan(whole: [0, 2, 3, 5], typed: [0, 1, 6], bytes: bytes)
        #expect(span == ScoredSpan(start: 2, owed: []))
    }

    @Test(
        "Only the token after a cut word that begins with its remainder is owed it; a boundary, a mismatch, the line's first token and an unknown id owe nothing."
    )
    func onlyAContinuingTokenIsOwed() {
        #expect(ScoredSpan(whole: [0, 4, 5], typed: [0, 1, 6], bytes: bytes)?.owed == Array("gi".utf8))
        #expect(ScoredSpan(whole: [0, 3, 5], typed: [0, 3], bytes: bytes) == ScoredSpan(start: 2, owed: []))
        #expect(ScoredSpan(whole: [0, 8, 5], typed: [0, 1], bytes: bytes) == ScoredSpan(start: 1, owed: []))
        #expect(ScoredSpan(whole: [3, 5], typed: [1, 6], bytes: bytes) == ScoredSpan(start: 1, owed: []))
        #expect(
            ScoredSpan(whole: [0, 99, 5], typed: [0, 1], bytes: bytes) == ScoredSpan(start: 1, owed: []))
        #expect(ScoredSpan(whole: [0, 9, 5], typed: [0, 1], bytes: bytes) == ScoredSpan(start: 1, owed: []))
    }

    @Test("The tokens a remainder could go on as are every token that writes it first.")
    func continuingTokens() {
        #expect(ScoredSpan.continuing(Array("gi".utf8), in: bytes) == [2, 3, 4])
        #expect(ScoredSpan.continuing([], in: bytes).isEmpty)
    }

    @Test(
        "A cut word's first token is read against the mass of its rivals, not against the whole vocabulary.")
    func theFirstTokenIsConditioned() {
        let git = log(Float(0.0004))
        let mass = ScoredSpan.logSumExp([git, log(Float(0.0001))])
        let scores = ScoredSpan.conditioned([git, -0.5], onMass: mass)
        #expect(abs(scores[0] - log(0.8)) < 1e-4)
        #expect(scores[1] == -0.5)
        #expect(ScoredSpan.conditioned([-1], onMass: -2) == [0])
        #expect(ScoredSpan.conditioned([-10, -0.5], onMass: nil) == [-10, -0.5])
        #expect(ScoredSpan.conditioned([], onMass: -1).isEmpty)
        #expect(ScoredSpan.logSumExp([]) == nil)
        #expect(ScoredSpan.logSumExp([-.infinity]) == nil)
    }
}
