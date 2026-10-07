// Runs the per-speaker confusion learning curve over decoded utterances, scoring every speaker against the others.
import Foundation

extension ConfusionLearningCurve {
    /// One line of the curve: a level (nil for the global key alone), k, a poisoning share and what it scored.
    public struct Row: Sendable, Equatable {
        public let level: Level?
        public let k: Int
        public let poisoning: Double
        /// Top-1 recall of the meant word, with a 95% interval from resampling whole speakers.
        public let recall: WordDoubtEvaluation.Interval?
        public let falseOverrideRate: Double
        /// Mean bytes of the fitted per-speaker models.
        public let storedBytes: Int
        /// Held-out corrections scored, over every speaker.
        public let trials: Int
    }

    /// Each speaker's corrections, in utterance order, read from the substitutions of their decoded utterances.
    public static func events(_ utterances: [HarvestUtterance]) -> [String: [Event]] {
        var bySpeaker: [String: [Event]] = [:]
        for utterance in utterances {
            for (meant, heard) in ConfusionHarvest.substitutions(utterance) {
                let soundClass = ConfusionClass(reference: meant, recognised: heard).rawValue
                bySpeaker[utterance.speaker, default: []].append(
                    Event(heard: heard, meant: meant, soundClass: soundClass))
            }
        }
        return bySpeaker
    }

    /// The trials for `test`: the heard, the meant and every word `global` pairs with the heard, scored by global share.
    public static func trials(_ test: [Event], global: [String: [String: Int]]) -> [Trial] {
        test.map { event in
            let seen = global[event.heard] ?? [:]
            let total = Double(seen.values.reduce(0, +))
            let words = Set(seen.keys).union([event.heard, event.meant]).sorted()
            let candidates = words.map { word in
                Candidate(
                    word: word, score: log((Double(seen[word] ?? 0) + 1) / (total + Double(words.count))),
                    soundClass: ConfusionClass(reference: word, recognised: event.heard).rawValue)
            }
            return Trial(heard: event.heard, meant: event.meant, candidates: candidates)
        }
    }

    /// The curve: for every k and poisoning share, each level against the global key, held out by speaker.
    public static func curve(
        _ speakers: [String: [Event]], ks: [Int] = [0, 5, 10, 20, 50], poisonings: [Double] = [0, 0.1, 0.3],
        seed: UInt64 = 1
    ) -> [Row] {
        let classes = ConfusionClass.allCases.count
        let vocabulary = Set(speakers.values.joined().map(\.meant)).sorted()
        var rows: [Row] = []
        for k in ks {
            for poisoning in poisonings {
                for level in [nil] + Level.allCases.map(Optional.some) {
                    if level == nil, poisoning > 0 { continue }
                    var scored: [WordDoubtEvaluation.Scored] = []
                    var overturned = 0.0
                    var baseRight = 0.0
                    var bytes: [Int] = []
                    for (speaker, events) in speakers.sorted(by: { $0.key < $1.key }) {
                        let (fit, test) = split(events, first: k)
                        guard !test.isEmpty else { continue }
                        let global = pairCounts(speakers.filter { $0.key != speaker }.flatMap(\.value))
                        let model = Model(
                            fitting: poisoned(fit, fraction: poisoning, vocabulary: vocabulary, seed: seed))
                        bytes.append(model.storedBytes)
                        let trials = trials(test, global: global)
                        for trial in trials {
                            let result = evaluate(
                                [trial], model: level == nil ? nil : model, level: level ?? .backOff,
                                classes: classes)
                            let base = evaluate([trial], model: nil, level: .backOff, classes: classes)
                            scored.append(
                                WordDoubtEvaluation.Scored(
                                    certainty: result.topOneRecall, isWrong: base.topOneRecall == 1,
                                    cluster: speaker))
                            if base.topOneRecall == 1 {
                                baseRight += 1
                                overturned += result.falseOverrideRate
                            }
                        }
                    }
                    let recall = WordDoubtEvaluation.clustered(scored, seed: seed, meanCertainty)
                    rows.append(
                        Row(
                            level: level, k: k, poisoning: poisoning, recall: recall,
                            falseOverrideRate: baseRight == 0 ? 0 : overturned / baseRight,
                            storedBytes: bytes.isEmpty ? 0 : bytes.reduce(0, +) / bytes.count,
                            trials: scored.count))
                }
            }
        }
        return rows
    }

    /// The curve as Markdown, one line per row.
    public static func markdown(_ rows: [Row]) -> String {
        let head =
            "| level | k | poisoning | trials | top-1 recall (95% CI) | false override | bytes |\n|---|---|---|---|---|---|---|"
        let body = rows.map { row in
            let recall =
                row.recall.map {
                    String(format: "%.1f%% (%.1f-%.1f)", $0.value * 100, $0.low * 100, $0.high * 100)
                } ?? "-"
            return "| \(row.level?.rawValue ?? "global key") | \(row.k) | \(Int(row.poisoning * 100))% | "
                + "\(row.trials) | \(recall) | \(String(format: "%.1f%%", row.falseOverrideRate * 100)) | \(row.storedBytes) |"
        }
        return ([head] + body).joined(separator: "\n")
    }

    private static func meanCertainty(_ sample: [WordDoubtEvaluation.Scored]) -> Double? {
        guard !sample.isEmpty else { return nil }
        let total: Double = sample.map(\.certainty).reduce(0, +)
        return total / Double(sample.count)
    }

    private static func pairCounts(_ events: [Event]) -> [String: [String: Int]] {
        var counts: [String: [String: Int]] = [:]
        for event in events { counts[event.heard, default: [:]][event.meant, default: 0] += 1 }
        return counts
    }
}
