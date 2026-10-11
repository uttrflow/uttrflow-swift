// Whether voiced audio that no recognised word covers predicts a word the recogniser left out.
private import NaturalLanguage
private import UttrflowCore

/// The kind of word a deletion took, for the classes whose loss changes the meaning.
public enum OmissionClass: String, Sendable, Equatable, CaseIterable, Codable {
    case negator
    case article
    case auxiliary
    case number
    case other

    /// The class of the word at `index` in `sentence`, read by the on-device tagger in context.
    public init(at index: Int, in sentence: [String]) {
        let word = sentence[index]
        let tag = LexicalClass.tag(ofWordAt: index, in: sentence)
        let lemma = LexicalClass.lemma(ofWordAt: index, in: sentence)
        if ["not", "no", "never"].contains(word) || word.hasSuffix("n't") {
            self = .negator
        } else if tag == .number || !word.isEmpty && word.allSatisfy(\.isNumber) {
            self = .number
        } else if tag == .determiner {
            self = .article
        } else if tag == .verb,
            ["be", "have", "do"].contains(lemma ?? word)
                || lemma == word && index + 1 < sentence.count
                    && LexicalClass.tag(ofWordAt: index + 1, in: sentence) == .verb
        {
            self = .auxiliary
        } else {
            self = .other
        }
    }
}

/// One recognised word and where it sits in the clip, in seconds.
public struct TimedWord: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A span of the clip, in seconds.
public struct TimeSpan: Sendable, Equatable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var length: Double { end - start }

    /// Whether the two spans share time once each is widened by `tolerance`.
    func overlaps(_ other: TimeSpan, tolerance: Double) -> Bool {
        start - tolerance < other.end && other.start < end + tolerance
    }
}

/// A reference word the recogniser left out, and the time between the recognised words either side of it.
public struct Omission: Sendable, Equatable {
    public let word: String
    public let kind: OmissionClass
    public let window: TimeSpan

    public init(word: String, kind: OmissionClass, window: TimeSpan) {
        self.word = word
        self.kind = kind
        self.window = window
    }
}

/// The deletions of one clip, the uncovered voiced runs in it, and the scoring of one against the other.
public enum OmissionCoverage {
    /// The minimum uncovered run lengths the report sweeps, in seconds.
    public static let sweep = [0.15, 0.3, 0.5]

    /// The precision the signal must reach before the review strip may use it.
    public static let precisionFloor = 0.5

    /// The reference words the timed `hypothesis` has no word for, each placed between its recognised neighbours.
    public static func omissions(reference: [String], hypothesis: [TimedWord], clip: TimeSpan) -> [Omission] {
        let alignment = WordErrorRate.measure(reference: reference, hypothesis: hypothesis.map(\.text))
            .alignment
        var omissions: [(word: String, index: Int, before: Int?)] = []
        var consumed = 0
        var read = 0
        for step in alignment {
            switch step {
            case .deletion(let word):
                omissions.append((word, read, consumed > 0 ? consumed - 1 : nil))
                read += 1
            case .match, .substitution:
                consumed += 1
                read += 1
            case .insertion: consumed += 1
            }
        }
        return omissions.map { item in
            let start = item.before.map { hypothesis[$0].end } ?? clip.start
            let next = (item.before ?? -1) + 1
            let end = next < hypothesis.count ? hypothesis[next].start : clip.end
            return Omission(
                word: item.word, kind: OmissionClass(at: item.index, in: reference),
                window: TimeSpan(start: min(start, end), end: max(start, end)))
        }
    }

    /// The parts of `voiced` no recognised word covers, at least `minimum` seconds long.
    public static func uncoveredRuns(voiced: TimeSpan, words: [TimedWord], minimum: Double) -> [TimeSpan] {
        var runs: [TimeSpan] = []
        var cursor = voiced.start
        for word in words.sorted(by: { $0.start < $1.start }) {
            if word.start > cursor { runs.append(TimeSpan(start: cursor, end: min(word.start, voiced.end))) }
            cursor = max(cursor, word.end)
            if cursor >= voiced.end { break }
        }
        if cursor < voiced.end { runs.append(TimeSpan(start: cursor, end: voiced.end)) }
        return runs.filter { $0.length >= minimum }
    }

    /// One decoded clip, ready to score.
    public struct Clip: Sendable, Equatable {
        public let reference: [String]
        public let words: [TimedWord]
        public let voiced: TimeSpan

        public init(reference: [String], words: [TimedWord], voiced: TimeSpan) {
            self.reference = reference
            self.words = words
            self.voiced = voiced
        }
    }

    /// Counts for one class at one minimum run length.
    public struct Tally: Sendable, Equatable {
        public var deletions = 0
        public var found = 0
        public var runs = 0
        public var runsNearDeletion = 0
        public var referenceWords = 0

        public init() {}

        /// Share of runs that sit near a deletion.
        public var precision: Double? { runs == 0 ? nil : Double(runsNearDeletion) / Double(runs) }
        /// Share of deletions with a run near them.
        public var recall: Double? { deletions == 0 ? nil : Double(found) / Double(deletions) }
        /// Runs near no deletion, per 100 reference words.
        public var falseAlarmsPer100Words: Double? {
            referenceWords == 0 ? nil : Double(runs - runsNearDeletion) * 100 / Double(referenceWords)
        }
    }

    /// Tallies `clips` at run length `minimum` within `tolerance` seconds; the `nil` key holds every class together.
    public static func tally(_ clips: [Clip], minimum: Double, tolerance: Double) -> [OmissionClass?: Tally] {
        var result: [OmissionClass?: Tally] = [:]
        for clip in clips {
            let omissions = omissions(reference: clip.reference, hypothesis: clip.words, clip: clip.voiced)
            let runs = uncoveredRuns(voiced: clip.voiced, words: clip.words, minimum: minimum)
            result[nil, default: Tally()].referenceWords += clip.reference.count
            result[nil, default: Tally()].runs += runs.count
            for run in runs where omissions.contains(where: { $0.window.overlaps(run, tolerance: tolerance) })
            {
                result[nil, default: Tally()].runsNearDeletion += 1
            }
            for omission in omissions {
                let near = runs.contains { $0.overlaps(omission.window, tolerance: tolerance) }
                for key in [nil, omission.kind] as [OmissionClass?] {
                    result[key, default: Tally()].deletions += 1
                    if near { result[key, default: Tally()].found += 1 }
                }
            }
        }
        return result
    }

    /// Whether the signal may feed the review strip: precision at or above the floor at some swept length.
    public static func isGo(_ overall: [Tally]) -> Bool {
        overall.contains { ($0.precision ?? 0) >= precisionFloor && ($0.recall ?? 0) > 0 }
    }
}
