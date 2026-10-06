import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("One doubt policy", .bug(id: 3975))
struct DoubtPolicyTests {
    /// One word heard at `confidence`: a homophone-group word, or one in no group.
    private static let table: [(word: String, confidence: Double, expected: DoubtReason?)] = [
        ("principal", 0.3, .lowScore), ("principal", 0.5, .homophoneClass),
        ("principal", 0.97, .homophoneClass),
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
