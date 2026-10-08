import Foundation
import Testing

@testable import UttrflowLocalModel
import UttrflowPredict

/// A line's score read from the pass that wrote it: only the tokens that wrote its words past the typing count.
@Suite("A generated line scored from its own pass")
struct GeneratedConfidenceTests {
    /// A vocabulary of whole pieces, each id writing its own text.
    private static let pieces = [
        "should", " go", " home", ".", " Then", " more", "git", " commit", " -m", "\n", " checkout", " main",
    ]
    private static let bytes = pieces.map { Array($0.utf8) }

    /// The ids that spell `words` in order.
    private static func ids(_ words: [String]) -> [Int] {
        words.compactMap { pieces.firstIndex(of: $0) }
    }

    @Test("Each token's bytes end where the ones before it and its own add up to.")
    func byteEndsAccumulate() {
        #expect(
            GeneratedConfidence.byteEnds(of: Self.ids(["should", " go", "."]), bytes: Self.bytes) == [
                6, 9, 10,
            ])
        #expect(GeneratedConfidence.byteEnds(of: [99], bytes: Self.bytes) == [0])
    }

    @Test("Only the tokens overlapping the range count toward the mean.")
    func overlappingTokensOnly() {
        let confidence = GeneratedConfidence.confidence(
            over: 4..<10, ends: [3, 6, 10], logProbabilities: [-0.1, -2, -0.5])
        #expect(confidence == -1.25)
        #expect(
            GeneratedConfidence.confidence(over: 20..<30, ends: [3, 6], logProbabilities: [-1, -1]) == nil)
    }

    @Test(
        "One token under the plausibility floor scores the line as that token, so a lone invention is never certain."
    )
    func implausibleTokenScoresTheLine() {
        let logProbabilities = Array(repeating: -0.02, count: 9) + [-7.5]
        let ends = Array(1...10)
        let confidence = GeneratedConfidence.confidence(
            over: 0..<10, ends: ends, logProbabilities: logProbabilities)
        #expect(confidence == -7.5)
        #expect(!Verification.clears(confidence, floor: Verification.certainFloor))
        #expect(!Verification.clears(confidence, floor: Verification.choiceFloor))
    }

    @Test("Tokens all at or over the plausibility floor still score the line by their mean.")
    func plausibleTokensKeepTheMean() {
        let confidence = GeneratedConfidence.confidence(
            over: 0..<2, ends: [1, 2], logProbabilities: [-0.5, Verification.plausibilityFloor])
        #expect(confidence == (-0.5 + Verification.plausibilityFloor) / 2)
    }

    @Test("A token that writes nothing never counts, and one past the recorded scores is ignored.")
    func emptyAndUnscoredTokensSkipped() {
        let confidence = GeneratedConfidence.confidence(
            over: 0..<10, ends: [3, 3, 6, 10], logProbabilities: [-1, -9, -3])
        #expect(confidence == -2)
    }

    @Test("The word the typing owed is not the model's claim, so the line is scored from its own words on.")
    func owedWordIsNotScored() {
        let tokens = Self.ids(["should", " go", " home", "."])
        let scored = GeneratedConfidence.confidences(
            of: ["I think we should go home."], typed: "I think we should", written: "I think we ",
            text: "should go home.", tokens: tokens, logProbabilities: [-0.01, -1, -2, -0.5],
            bytes: Self.bytes)
        #expect(abs((scored["I think we should go home."] ?? 0) - (-3.5 / 3)) < 1e-9)
    }

    @Test("A line the parser cut is scored only up to its cut, never on the words it dropped.")
    func cutLineStopsAtItsEnd() {
        let tokens = Self.ids(["should", " go", " home", ".", " Then", " more"])
        let scored = GeneratedConfidence.confidences(
            of: ["I think we should go home."], typed: "I think we should", written: "I think we ",
            text: "should go home. Then more", tokens: tokens, logProbabilities: [0, -1, -1, -1, -9, -9],
            bytes: Self.bytes)
        #expect(scored["I think we should go home."] == -1)
    }

    @Test("Several lines from one pass are each found after the one before.")
    func linesFoundInOrder() {
        let tokens = Self.ids(["git", " commit", " -m", "\n", "git", " checkout", " main", "\n"])
        let scored = GeneratedConfidence.confidences(
            of: ["git commit -m", "git checkout main"], typed: "git c", written: "",
            text: "git commit -m\ngit checkout main\n", tokens: tokens,
            logProbabilities: [0, -1, -1, 0, 0, -3, -3, 0], bytes: Self.bytes)
        #expect(scored["git commit -m"] == -1)
        #expect(scored["git checkout main"] == -3)
    }

    @Test("A line the pass never spelt, or one adding nothing to the typing, is left unscored.")
    func unplacedLinesUnscored() {
        let tokens = Self.ids(["git", " commit"])
        let scored = GeneratedConfidence.confidences(
            of: ["git clone", "git c"], typed: "git c", written: "", text: "git commit", tokens: tokens,
            logProbabilities: [0, -1], bytes: Self.bytes)
        #expect(scored.isEmpty)
    }

    @Test("A line reshaped by the parser is found by its tail alone.")
    func reshapedLineFoundByTail() {
        let span = GeneratedConfidence.span(
            of: "Git commit", typed: "git c", in: Array("- git commit".utf8), from: 0)
        #expect(span?.0 == 7)
        #expect(span?.1 == 12)
        #expect(
            GeneratedConfidence.span(of: "git c", typed: "git c", in: Array("git c".utf8), from: 0) == nil)
    }

    @Test("The memory answers with the newest pass's score and forgets the oldest past its capacity.")
    func memoryKeepsTheNewest() {
        var memory = ConfidenceMemory()
        memory.remember(["git commit -m": -1])
        memory.remember(["git commit -m": -0.5])
        #expect(memory.confidence(of: "git commit -m") == -0.5)
        for index in 0..<ConfidenceMemory.capacity {
            memory.remember(["line \(index)": -1])
        }
        #expect(memory.confidence(of: "git commit -m") == nil)
        #expect(memory.confidence(of: "line 0") == -1)
        memory.forgetEverything()
        #expect(memory.confidence(of: "line 0") == nil)
    }
}
