// The per-speaker confusion model probe: how fast learning a speaker's misheard words improves candidate ranking.
import Foundation

/// A two-level confusion model fitted on one speaker's corrections, scored as a feature beside the global key.
public enum ConfusionLearningCurve {
    /// One correction: the word written, the word meant, and the sound class the substitution fell in.
    public struct Event: Sendable, Equatable, Codable {
        public let heard: String
        public let meant: String
        public let soundClass: String

        public init(heard: String, meant: String, soundClass: String) {
            self.heard = heard
            self.meant = meant
            self.soundClass = soundClass
        }
    }

    /// Which levels of the model are consulted.
    public enum Level: String, CaseIterable, Sendable {
        /// Sound-class counts only, smoothed toward uniform.
        case soundClass
        /// Word-pair counts only.
        case wordPair
        /// Word-pair counts, backing off to sound-class counts for an unseen pair.
        case backOff
    }

    /// The counts fitted from a speaker's first corrections.
    public struct Model: Sendable, Equatable, Codable {
        public private(set) var classCounts: [String: Int] = [:]
        public private(set) var pairCounts: [String: Int] = [:]
        public private(set) var heardCounts: [String: Int] = [:]
        public private(set) var total = 0

        /// A model fitted on `events`.
        public init(fitting events: [Event]) {
            for event in events {
                classCounts[event.soundClass, default: 0] += 1
                pairCounts[Self.key(event.heard, event.meant), default: 0] += 1
                heardCounts[event.heard, default: 0] += 1
                total += 1
            }
        }

        /// Bytes the model takes stored as JSON.
        public var storedBytes: Int { (try? JSONEncoder().encode(self).count) ?? 0 }

        /// Log-ratio of the smoothed class probability to uniform over `classes`; 0 with no data.
        public func classLogRatio(_ soundClass: String, classes: Int, alpha: Double = 1) -> Double {
            let count = Double(classCounts[soundClass] ?? 0)
            let smoothed = (count + alpha) / (Double(total) + alpha * Double(classes))
            return log(smoothed * Double(classes))
        }

        /// Log-ratio for writing `heard` when `meant` was said, at `level`.
        public func logRatio(
            heard: String, meant: String, soundClass: String, classes: Int, level: Level
        ) -> Double {
            let pair = Double(pairCounts[Self.key(heard, meant)] ?? 0)
            let seen = Double(heardCounts[heard] ?? 0)
            let pairRatio = pair > 0 ? log((pair + 1) / (seen + 1) * 2) : 0
            switch level {
            case .soundClass: return classLogRatio(soundClass, classes: classes)
            case .wordPair: return pairRatio
            case .backOff: return pair > 0 ? pairRatio : classLogRatio(soundClass, classes: classes)
            }
        }

        private static func key(_ heard: String, _ meant: String) -> String { heard + "\u{1F}" + meant }
    }

    /// A test case: what was written, what was meant, and the candidates the existing sources offer with their scores.
    public struct Trial: Sendable, Equatable {
        public let heard: String
        public let meant: String
        public let candidates: [Candidate]

        public init(heard: String, meant: String, candidates: [Candidate]) {
            self.heard = heard
            self.meant = meant
            self.candidates = candidates
        }
    }

    /// A candidate replacement with the global key's score and the sound class of the substitution.
    public struct Candidate: Sendable, Equatable {
        public let word: String
        public let score: Double
        public let soundClass: String

        public init(word: String, score: Double, soundClass: String) {
            self.word = word
            self.score = score
            self.soundClass = soundClass
        }
    }

    /// Top-1 recall of the meant word and the share of trials the global key had right that the model overturned.
    public struct Result: Sendable, Equatable {
        public let topOneRecall: Double
        public let falseOverrideRate: Double
    }

    /// Scores `trials` with the global key alone (nil model) or with the model's log-ratio added.
    public static func evaluate(
        _ trials: [Trial], model: Model?, level: Level, classes: Int, weight: Double = 1
    ) -> Result {
        guard !trials.isEmpty else { return Result(topOneRecall: 0, falseOverrideRate: 0) }
        var hits = 0
        var baseRight = 0
        var overturned = 0
        for trial in trials {
            let base = top(trial.candidates) { $0.score }
            let ranked = top(trial.candidates) { candidate in
                candidate.score + weight
                    * (model?.logRatio(
                        heard: trial.heard, meant: candidate.word, soundClass: candidate.soundClass,
                        classes: classes, level: level) ?? 0)
            }
            if ranked == trial.meant { hits += 1 }
            if base == trial.meant {
                baseRight += 1
                if ranked != trial.meant { overturned += 1 }
            }
        }
        return Result(
            topOneRecall: Double(hits) / Double(trials.count),
            falseOverrideRate: baseRight == 0 ? 0 : Double(overturned) / Double(baseRight))
    }

    /// Splits one speaker's events, in time order, into the first `k` and the rest.
    public static func split<Element>(_ ordered: [Element], first k: Int) -> (fit: [Element], test: [Element])
    {
        let cut = min(max(k, 0), ordered.count)
        return (Array(ordered[..<cut]), Array(ordered[cut...]))
    }

    /// `events` with `fraction` of them replaced by a pair drawn at random from `vocabulary`, seeded and repeatable.
    public static func poisoned(
        _ events: [Event], fraction: Double, vocabulary: [String], seed: UInt64
    ) -> [Event] {
        guard !vocabulary.isEmpty else { return events }
        var state = seed
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let count = Int((Double(events.count) * fraction).rounded())
        return events.enumerated().map { index, event in
            guard index < count else { return event }
            let meant = vocabulary[Int(next() % UInt64(vocabulary.count))]
            return Event(heard: event.heard, meant: meant, soundClass: event.soundClass)
        }
    }

    private static func top(_ candidates: [Candidate], by score: (Candidate) -> Double) -> String? {
        candidates.max { score($0) < score($1) }?.word
    }
}
