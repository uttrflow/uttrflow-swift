import Foundation
import Hub
import Testing
import Tokenizers

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

    @Test("The divergence read back from the line's own tokens is the one its typed opening gives.")
    func theLineAloneGivesTheSameDivergence() {
        let cases: [(whole: [Int], typed: [Int], continuation: String)] = [
            ([0, 3, 5], [0, 1, 6], "t status"),
            ([0, 10, 11, 5], [0, 12, 13], "s status"),
            ([0, 2, 3, 5], [0, 1, 6], "git status"),
            ([0, 4, 5], [0, 1, 6], "st status"),
            ([0, 3, 5], [0, 3], " status"),
        ]
        for (whole, typed, continuation) in cases {
            #expect(
                ScoredSpan.divergence(whole: whole, continuation: Array(continuation.utf8), bytes: bytes)
                    == ScoredSpan.divergence(whole: whole, typed: typed, bytes: bytes),
                "continuation \(continuation.debugDescription)")
        }
    }

    @Test("A line whose tokens cannot be read back as the continuation gives no divergence.")
    func bytesThatDoNotSpellTheContinuation() {
        // A vocabulary holding no bytes at all, an id it does not hold, and one that writes nothing.
        #expect(ScoredSpan.divergence(whole: [0, 3, 5], continuation: [0x74], bytes: []) == nil)
        #expect(
            ScoredSpan.divergence(whole: [0, 99, 5], continuation: Array("gi status".utf8), bytes: bytes)
                == nil)
        #expect(
            ScoredSpan.divergence(whole: [0, 9, 5], continuation: Array("gi status".utf8), bytes: bytes)
                == nil)
        // The tail spells something else, and the line runs out of tokens before the continuation does.
        #expect(
            ScoredSpan.divergence(whole: [0, 3, 5], continuation: Array("t statuz".utf8), bytes: bytes) == nil
        )
        #expect(ScoredSpan.divergence(whole: [3], continuation: Array("a git".utf8), bytes: bytes) == nil)
    }

    @Test("A line adding nothing past what was typed has nothing to judge, however the divergence is read.")
    func nothingPastTheTypedOpening() {
        let divergence = ScoredSpan.divergence(whole: [0, 3], continuation: [], bytes: bytes)
        #expect(divergence == ScoredSpan.Divergence(index: 2, owed: []))
        #expect(
            ScoredSpan(whole: [0, 3], past: divergence ?? .init(index: 0, owed: []), bytes: bytes) == nil)
    }

    @Test("The tokens a remainder could go on as are every token that writes it first.")
    func continuingTokens() {
        #expect(ScoredSpan.continuing(Array("gi".utf8), in: bytes) == [2, 3, 4])
        #expect(ScoredSpan.continuing([], in: bytes).isEmpty)
        let vocabulary = TokenHealing.Vocabulary(bytes: bytes, ending: [])
        #expect(ScoredSpan.continuing(Array("gi".utf8), in: vocabulary) == [2, 3, 4])
        #expect(ScoredSpan.continuing(Array("absent".utf8), in: vocabulary).isEmpty)
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
        #expect(ScoredSpan.conditioned([-0.25], onMass: .nan) == [-Double.infinity])
        #expect(ScoredSpan.conditioned([-0.25], onMass: .infinity) == [-Double.infinity])
        #expect(ScoredSpan.conditioned([], onMass: -1).isEmpty)
        #expect(ScoredSpan.logSumExp([]) == nil)
        #expect(ScoredSpan.logSumExp([-.infinity]) == nil)
    }
}

/// The context and the whole line a real pass judges, taken from the lines `Docs/predict.md` measures the floor and the mid-word cut on.
private let realCandidates: [(context: String, candidate: String)] = [
    ("ls", "ls -l"), ("ls", "ls -la"), ("ls", "ls --zzqx-bogus"), ("ls ", "ls -l"),
    ("git c", "git commit -m"), ("git c", "git checkout main"), ("git c", "git cxq"),
    ("git c", "git comit -m"), ("gi", "git status"), ("gi", "git checkout main"),
    ("gi", "gizmo --frobnicate"), ("l", "ls -la"), ("git sta", "git stash pop"),
    ("git s", "Git status"), ("gti s", "git status"), ("SELE", "SELECT * FROM uzqx WHERE"),
    ("SELECT * FROM u", "SELECT * FROM users"), ("SELECT * FROM u", "SELECT * FROM uzqx WHERE"),
    ("Deploy the re", "Deploy the release candidate to production"),
    ("Deploy the re", "Deploy the rezzq flombat"), ("caf", "caf\u{E9} au lait, please"),
    ("haan", "haan thik hai bhai"), ("https://exa", "https://example.com/pricing"),
    ("Thanks for sending the draft ov", "Thanks for sending the draft over, I will check the venue"),
    ("", "ls -l"), ("ls -l", "ls -l"),
]

@Suite("Reading a typed opening back from the line's own tokens")
struct ScoredSpanProofTests {
    /// The suggestion model's snapshot, when this Mac has it.
    static let gemmaSnapshot = CachedSnapshot.complete(
        identifier: LocalModel.gemma3.identifier, revision: LocalModel.gemma3.revision,
        in: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/huggingface/hub"),
        minimumWeightBytes: 0)

    @Test(
        "With Gemma 3's own tokenizer, every real candidate's span is the one tokenising its opening gives.",
        .enabled(if: gemmaSnapshot != nil, "needs Gemma 3 in the Hugging Face cache"))
    func gemmaSpansAreIdentical() async throws {
        let folder = try #require(Self.gemmaSnapshot)
        let tokenizer = try await AutoTokenizer.from(modelFolder: folder)
        var written: [[UInt8]] = []
        for id in 0..<TokenHealing.Vocabulary.mostTokens {
            guard let piece = tokenizer.convertIdToToken(id) else { break }
            written.append(TokenHealing.Vocabulary.bytes(of: piece))
        }
        for (context, candidate) in realCandidates {
            let whole = tokenizer.encode(text: MLXCandidateScorer.leadIn + candidate)
            let typed = CompletionText.typedPart(of: candidate, following: context)
            let read = ScoredSpan.divergence(
                whole: whole, continuation: Array(candidate.dropFirst(typed.count).utf8), bytes: written)
            let tokenised = ScoredSpan.divergence(
                whole: whole,
                typed: tokenizer.encode(text: MLXCandidateScorer.leadIn + typed), bytes: written)
            #expect(read == tokenised, "\(context.debugDescription) -> \(candidate.debugDescription)")
        }
    }
}
