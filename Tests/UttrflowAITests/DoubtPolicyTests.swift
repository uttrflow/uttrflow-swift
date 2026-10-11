import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("One doubt policy", .bug(id: 3975))
struct DoubtPolicyTests {
    /// One word heard at `confidence`: an ordinary word with an ordinary homophone, or one with none.
    private static let table: [(word: String, confidence: Double, expected: DoubtReason?)] = [
        ("write", 0.3, .lowScore), ("write", 0.5, .homophoneClass),
        ("write", 0.97, .homophoneClass),
        ("deploy", 0.3, .lowScore), ("deploy", 0.49, .lowScore), ("deploy", 0.5, nil), ("deploy", 0.97, nil),
    ]

    @Test("the policy answers the table")
    func policyAnswersTheTable() {
        for row in Self.table {
            #expect(DoubtPolicy.reason(text: row.word, confidence: row.confidence) == row.expected, "\(row)")
        }
    }

    @Test("the engine's runs, the doubtful words, the rules-alone route and the guard read the same policy")
    func everyCallerAgrees() {
        for row in Self.table {
            let words = [TranscribedWord(text: row.word, confidence: row.confidence)]
            let segment = TranscriptionSegment(text: row.word, start: .zero, end: .seconds(1), words: words)
            let transcription = Transcription(text: row.word, segments: [segment])
            let utterance = Utterance(words: [SpokenWord(text: row.word, confidence: row.confidence)])
            let draft = Draft(transcription: transcription)
            #expect(UncertainSpan.spans(in: utterance).first?.reason == row.expected, "\(row)")
            #expect(UncertainSpan.spans(in: draft).first?.reason == row.expected, "\(row)")
            let routed = RulesAlone.shortReplies.covers(TransformationRequest(transcription: transcription))
            #expect(routed == (row.expected == nil), "\(row)")
            #expect(DoubtPolicy.isHeardSurely(row.confidence) == (row.expected != .lowScore), "\(row)")
        }
    }

    @Test("a settled word is never doubted and is protected, whatever its score", .bug(id: 4519))
    func settledWordIsProtected() {
        #expect(DoubtPolicy.reason(text: "principal", confidence: 0.2, settled: true) == nil)
        #expect(DoubtPolicy.isProtected(confidence: 0.2, settled: true))
        #expect(!DoubtPolicy.isProtected(confidence: 0.2, settled: false))
        let words = [TranscribedWord(text: "Kubernetes", confidence: 0.2, settled: true)]
        let segment = TranscriptionSegment(text: "Kubernetes", start: .zero, end: .seconds(1), words: words)
        let transcription = Transcription(text: "Kubernetes", segments: [segment])
        #expect(UncertainSpan.spans(in: Draft(transcription: transcription)).isEmpty)
        #expect(RulesAlone.shortReplies.covers(TransformationRequest(transcription: transcription)))
    }

    @Test("no source outside the policy compares a confidence with the certainty threshold")
    func thresholdLivesInThePolicyAlone() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/UttrflowAI")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let file as URL in files
        where file.pathExtension == "swift" && file.lastPathComponent != "DoubtPolicy.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("certaintyThreshold") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty)
    }
}

@Suite("Override less, flag more", .bug(id: 6216))
struct DoubtDirectionTests {
    /// Invented sentence pairs: the heard reading and a candidate, crossed with generated words.
    private static func generatedPairs() -> [(heard: String, candidate: String)] {
        let subjects = ["we", "the team", "she", "they", "our build"]
        let verbs = ["can", "can't", "will", "won't", "did", "didn't"]
        let amounts = ["fifteen", "fifty", "two", "three", "a hundred", "a thousand", "some"]
        let objects = ["ship it", "files", "tests", "minutes", "the draft"]
        var pairs: [(String, String)] = []
        for subject in subjects {
            for verb in verbs {
                for amount in amounts {
                    for object in objects {
                        let heard = "\(subject) \(verb) send \(amount) \(object)"
                        for other in verbs + amounts where other != verb && other != amount {
                            let candidate =
                                verbs.contains(other)
                                ? "\(subject) \(other) send \(amount) \(object)"
                                : "\(subject) \(verb) send \(other) \(object)"
                            pairs.append((heard, candidate))
                            if pairs.count >= 2_000 { return pairs }
                        }
                    }
                }
            }
        }
        return pairs
    }

    private static func cost(of pair: (heard: String, candidate: String)) -> ConfusionCost {
        ConfusionCost.of(heard: pair.heard, candidate: pair.candidate)
    }

    private static let orderedConsequences: [Consequence] = [.stores, .sends, .executes]

    @Test("a pair is classed by negation, then quantity, else spelling")
    func classesPairs() {
        #expect(ConfusionCost.of(heard: "we can ship", candidate: "we can't ship") == .meaningFlip)
        #expect(ConfusionCost.of(heard: "we don't ship", candidate: "we won't ship") == .cosmetic)
        #expect(ConfusionCost.of(heard: "fifteen files", candidate: "fifty files") == .numberFlip)
        #expect(ConfusionCost.of(heard: "15 files", candidate: "50 files") == .numberFlip)
        #expect(ConfusionCost.of(heard: "their files", candidate: "there files") == .cosmetic)
    }

    @Test("the cheapest tier is today's behaviour")
    func cheapestTierUnchanged() {
        #expect(DoubtPolicy.OverridePolicy.requiredMargin(cost: .cosmetic, consequence: .stores) == 2)
        #expect(
            DoubtPolicy.FlagPolicy.flagLine(cost: .cosmetic, consequence: .stores)
                == DoubtPolicy.certaintyThreshold)
    }

    @Test("raising cost or consequence never raises overrides and never lowers flags")
    func monotone() {
        let pairs = Self.generatedPairs()
        #expect(pairs.count == 2_000)
        let margins = Array(0...6)
        let confidences = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
        for consequence in Self.orderedConsequences {
            var lastOverrides = Int.max
            var lastFlags = -1
            for cost in ConfusionCost.allCases {
                let overrides = margins.filter {
                    DoubtPolicy.OverridePolicy.allows(margin: $0, cost: cost, consequence: consequence)
                }.count
                let flags = confidences.filter {
                    DoubtPolicy.FlagPolicy.flags(confidence: $0, cost: cost, consequence: consequence)
                }.count
                #expect(overrides <= lastOverrides && flags >= lastFlags, "\(cost) \(consequence)")
                lastOverrides = overrides
                lastFlags = flags
            }
        }
        for cost in ConfusionCost.allCases {
            var lastOverrides = Int.max
            var lastFlags = -1
            for consequence in Self.orderedConsequences {
                let overrides = pairs.indices.filter { index in
                    let pairCost = max(cost, Self.cost(of: pairs[index]))
                    return DoubtPolicy.OverridePolicy.allows(
                        margin: index % 7, cost: pairCost, consequence: consequence)
                }.count
                let flags = pairs.indices.filter { index in
                    let pairCost = max(cost, Self.cost(of: pairs[index]))
                    return DoubtPolicy.FlagPolicy.flags(
                        confidence: Double(index % 21) / 20, cost: pairCost, consequence: consequence)
                }.count
                #expect(overrides <= lastOverrides && flags >= lastFlags, "\(cost) \(consequence)")
                lastOverrides = overrides
                lastFlags = flags
            }
        }
    }

    @Test("no source outside the policy holds an override margin or flag line")
    func thresholdsLiveInThePolicyAlone() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/UttrflowAI")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let file as URL in files
        where file.pathExtension == "swift" && file.lastPathComponent != "DoubtPolicy.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if ["improvementMargin", "baseMargin", "stepPerTier"].contains(where: text.contains) {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty)
    }
}
