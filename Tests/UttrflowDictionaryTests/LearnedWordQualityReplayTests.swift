// A replay gate: a week of invented dictations through the learner, scored for real terms against junk.

import Foundation
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowDictionary

/// What the replay learnt, scored against the labels.
private struct ReplayScore: CustomStringConvertible {
    let learned: [String]
    let real: [String]
    let junk: [String]
    let missed: [String]

    /// The share of learned words that were real terms, as a whole percentage; 100 when nothing was learnt.
    var realSharePercent: Int { learned.isEmpty ? 100 : real.count * 100 / learned.count }

    var description: String {
        "learned \(learned.count), real \(real.count) (\(realSharePercent)%), junk \(junk.count) \(junk.sorted()), "
            + "missed \(missed.count) \(missed.sorted())"
    }
}

/// The replay in spoken order, half an hour apart.
private var replay: [LearnedWordReplay.Dictation] { LearnedWordReplay.dictations }

/// The labels, read from the shared corpus.
private let realTerms = LearnedWordReplay.realTerms
private let junkTerms = LearnedWordReplay.junkTerms

/// The ratchet: lower these when the learner improves; a rule change that raises junk or lowers the share fails.
private enum ReplayBaseline {
    static let junkLearned = 2
    static let realSharePercent = 81
    static let termsMissed = 7
}

@Suite("A replayed week of invented dictations, scored for real terms against junk")
struct LearnedWordQualityReplayTests {
    @Test("The replay holds at least 200 dictations across 8 application families")
    func replayIsLargeEnough() {
        #expect(replay.count >= 200)
        #expect(Set(replay.map(\.application)).count == 8)
    }

    @Test("Junk learned and terms missed never rise, and the real share never falls")
    func learnedWordQualityHoldsTheBaseline() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let start = Date(timeIntervalSinceReferenceDate: 0)

        var learned: [String] = []
        for (index, dictation) in replay.enumerated() {
            learned += try await store.learn(
                heard: dictation.heard, wrote: dictation.wrote,
                seeing: AppContext(
                    applicationName: dictation.application, documentName: dictation.title,
                    selectedText: dictation.selection),
                at: start.addingTimeInterval(Double(index) * 1_800)
            ).map(\.word)
        }

        let lowered = Set(learned.map { $0.lowercased() })
        let score = ReplayScore(
            learned: learned,
            real: learned.filter { realTerms.contains($0.lowercased()) },
            junk: learned.filter { !realTerms.contains($0.lowercased()) },
            missed: realTerms.subtracting(lowered).sorted())
        print("Learned-word replay: \(score)")

        #expect(score.junk.count <= ReplayBaseline.junkLearned, "\(score)")
        #expect(score.realSharePercent >= ReplayBaseline.realSharePercent, "\(score)")
        #expect(score.missed.count <= ReplayBaseline.termsMissed, "\(score)")
        #expect(junkTerms.isDisjoint(with: realTerms))
    }
}
