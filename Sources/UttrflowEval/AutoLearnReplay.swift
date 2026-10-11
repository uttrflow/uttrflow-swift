// The offline replay that scores what the pair learner learns from synthetic edits. See Docs/eval-methodology.md.
import Foundation
private import UttrflowDictionary

/// Feeds true fixes and decoy edits through the default pair learner and scores the dictionary that results.
package enum AutoLearnReplay {
    /// The most learnt pairs that may be anything but a true fix, as a share of all learnt pairs.
    package static let maximumFalseLearnRate = 0.05
    /// The most decoy-born pairs the learner may keep: none.
    package static let maximumDecoyPairs = 0
    /// The most held-out words the learnt dictionary may rewrite wrongly, as a share of all held-out words.
    package static let maximumFalseOverrideRate = 0.01

    /// What an edit really was.
    package enum Kind: Sendable, Equatable {
        case trueFix
        case decoy(Decoy)
    }

    /// An edit that is not a person correcting a misheard word.
    package enum Decoy: String, Sendable, CaseIterable {
        /// The field rewrote a word on its own, so the same pair repeats in a burst.
        case autocorrect
        /// The person changed their mind about the wording.
        case rewrite
        /// A slip of the keys, never made twice.
        case typo
    }

    /// One edit on one day: the form inserted and the form the person left.
    package struct Edit: Sendable, Equatable {
        package let day: Int
        package let heard: String
        package let meant: String
        package let kind: Kind
    }

    /// What the replay measured.
    package struct Report: Sendable, Equatable {
        package let trueFixPairs: Int
        package let learntPairs: Int
        package let learntTrueFixes: Int
        package let learntFromDecoys: Int
        package let heldOutWords: Int
        package let falseOverrides: Int

        /// The share of learnt pairs that are true fixes; 1 when nothing is learnt.
        package var precision: Double { learntPairs == 0 ? 1 : Double(learntTrueFixes) / Double(learntPairs) }
        /// The share of learnt pairs that are not true fixes.
        package var falseLearnRate: Double { 1 - precision }
        /// The share of distinct true fixes that were learnt.
        package var recall: Double { trueFixPairs == 0 ? 0 : Double(learntTrueFixes) / Double(trueFixPairs) }
        /// The share of held-out words the learnt dictionary would rewrite although the reference keeps them.
        package var falseOverrideRate: Double {
            heldOutWords == 0 ? 0 : Double(falseOverrides) / Double(heldOutWords)
        }

        /// Whether the default settings meet every bound in code.
        package var meetsBounds: Bool {
            falseLearnRate <= AutoLearnReplay.maximumFalseLearnRate
                && learntFromDecoys <= AutoLearnReplay.maximumDecoyPairs
                && falseOverrideRate <= AutoLearnReplay.maximumFalseOverrideRate
        }

        /// The report as a short table.
        package var markdown: String {
            func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
            return """
                | Measure | Value | Bound |
                |---|---|---|
                | True-fix pairs | \(trueFixPairs) | |
                | Learnt pairs | \(learntPairs) | |
                | Precision | \(percent(precision)) | false-learn at most \(percent(Self.bound)) |
                | Recall | \(percent(recall)) | |
                | Pairs learnt from decoys | \(learntFromDecoys) | at most \(AutoLearnReplay.maximumDecoyPairs) |
                | False overrides on held-out | \(falseOverrides) of \(heldOutWords) (\(percent(falseOverrideRate))) \
                | at most \(percent(AutoLearnReplay.maximumFalseOverrideRate)) |
                """
        }

        private static var bound: Double { AutoLearnReplay.maximumFalseLearnRate }
    }

    /// The single-word substitutions between each case's heard and reference text, with the held-out words of the rest.
    package static func scenario(from cases: [EvaluationCase]) -> (edits: [Edit], heldOut: [String]) {
        var fixes: [(heard: String, meant: String)] = []
        var heldOut: [String] = []
        for item in cases where item.language == .english {
            let misheard = item.category == .homophone
            if misheard, let pair = substitution(heard: item.spoken, meant: item.expected) {
                if !fixes.contains(where: { $0.heard == pair.heard && $0.meant == pair.meant }) {
                    fixes.append(pair)
                }
            } else {
                heldOut += words(of: item.expected)
            }
        }
        return (edits(fixes: fixes, vocabulary: Array(Set(heldOut)).sorted()), heldOut)
    }

    /// Runs the default learner over the edits in day order and scores what it learnt.
    package static func replay(_ edits: [Edit], heldOut: [String]) -> Report {
        var ledger = PairLedger()
        var learnt: [(heard: String, meant: String)] = []
        for edit in edits.sorted(by: { $0.day < $1.day }) {
            if let pair = ledger.record(heard: edit.heard, meant: edit.meant, on: edit.day).learnt {
                learnt.append((pair.heard, pair.meant))
            }
        }
        let trueKeys = Set(edits.filter { $0.kind == .trueFix }.map { key($0.heard, $0.meant) })
        let decoyKeys = Set(edits.filter { $0.kind != .trueFix }.map { key($0.heard, $0.meant) })
        let rewritten = Set(learnt.map { $0.heard.lowercased() })
        return Report(
            trueFixPairs: trueKeys.count, learntPairs: learnt.count,
            learntTrueFixes: learnt.filter { trueKeys.contains(key($0.heard, $0.meant)) }.count,
            learntFromDecoys: learnt.filter { decoyKeys.contains(key($0.heard, $0.meant)) }.count,
            heldOutWords: heldOut.count, falseOverrides: heldOut.filter { rewritten.contains($0) }.count)
    }

    /// The synthetic fortnight: each true fix recurs on separate days, except every third, which is seen on one.
    private static func edits(fixes: [(heard: String, meant: String)], vocabulary: [String]) -> [Edit] {
        var edits: [Edit] = []
        for (index, fix) in fixes.enumerated() {
            let days: [Int]
            switch index % 3 {
            case 0: days = [1, 3, 8]
            case 1: days = [2, 4, 4]
            default: days = [5]
            }
            edits += days.map { Edit(day: $0, heard: fix.heard, meant: fix.meant, kind: .trueFix) }
        }
        for (index, word) in vocabulary.filter({ $0.count > 3 && $0.allSatisfy(\.isLetter) }).prefix(24)
            .enumerated()
        {
            let day = 1 + index % 12
            let slipped = String(word.dropLast(2) + word.suffix(2).reversed())
            edits.append(Edit(day: day, heard: slipped, meant: word, kind: .decoy(.typo)))
            let other = vocabulary[(index * 7 + 3) % vocabulary.count]
            let sightings = index % 2 == 0 ? 1 : 2
            for repeatDay in 0..<sightings {
                edits.append(
                    Edit(
                        day: 1 + (index + repeatDay * 5) % 12, heard: word, meant: other,
                        kind: .decoy(.rewrite)))
            }
        }
        for (index, pair) in [("teh", "the"), ("recieve", "receive"), ("wont", "won't")].enumerated() {
            edits += (0..<6).map { _ in
                Edit(day: 2 + index * 3, heard: pair.0, meant: pair.1, kind: .decoy(.autocorrect))
            }
        }
        return edits
    }

    /// The one word that differs when both texts have the same words otherwise.
    private static func substitution(heard: String, meant: String) -> (heard: String, meant: String)? {
        let (left, right) = (words(of: heard), words(of: meant))
        guard left.count == right.count else { return nil }
        let differing = zip(left, right).filter { $0 != $1 }
        guard differing.count == 1, let pair = differing.first else { return nil }
        return (pair.0, pair.1)
    }

    private static func words(of text: String) -> [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).compactMap { token in
            let kept = token.trimmingCharacters(in: .punctuationCharacters)
            return kept.isEmpty ? nil : kept
        }
    }

    private static func key(_ heard: String, _ meant: String) -> String {
        heard.lowercased() + "\u{1F}" + meant.lowercased()
    }
}
