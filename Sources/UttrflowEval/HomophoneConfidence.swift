// Whether the recogniser's word score separates a misheard homophone from a word heard right.
private import UttrflowCore

/// One homophone pair read inside an invented sentence that means `meant`.
public struct HomophonePair: Sendable, Equatable {
    /// The member the sentence means.
    public let meant: String
    /// The member that sounds the same and is the likely misreading.
    public let other: String
    /// The invented sentence, holding `meant` once.
    public let sentence: String

    /// A pair read in a sentence.
    public init(meant: String, other: String, sentence: String) {
        self.meant = meant
        self.other = other
        self.sentence = sentence
    }
}

/// The pairs, the outcome of one decode, and the statistics a table of them reports.
public enum HomophoneConfidence {
    /// The score under which the correction engine doubts a word (`CorrectionEngine.certaintyThreshold`).
    public static let gate = 0.5

    /// The sentence spoken before the pair's sentence in the developer-prefix condition.
    public static let developerPrefix = "I am working in the terminal on the build script."

    /// Programmer terms whose spoken form matches an everyday word.
    public static let programmerPairs: [HomophonePair] = [
        HomophonePair(meant: "cache", other: "cash", sentence: "clear the cache before the next run"),
        HomophonePair(meant: "byte", other: "bite", sentence: "the header takes one byte per field"),
        HomophonePair(meant: "root", other: "route", sentence: "log in as root on the test box"),
        HomophonePair(meant: "queue", other: "cue", sentence: "push the job onto the queue"),
        HomophonePair(meant: "sync", other: "sink", sentence: "run a sync before you close the laptop"),
        HomophonePair(meant: "sed", other: "said", sentence: "use sed to swap the names in the file"),
        HomophonePair(meant: "suite", other: "sweet", sentence: "the whole test suite passes now"),
        HomophonePair(meant: "build", other: "billed", sentence: "the build failed on the second step"),
        HomophonePair(meant: "pane", other: "pain", sentence: "split the terminal into a second pane"),
        HomophonePair(meant: "kernel", other: "colonel", sentence: "the kernel panics when the driver loads"),
        HomophonePair(meant: "hertz", other: "hurts", sentence: "measure the rate in hertz"),
        HomophonePair(meant: "core", other: "corps", sentence: "pin the worker to one core"),
        HomophonePair(meant: "cron", other: "crone", sentence: "the cron job runs every hour"),
        HomophonePair(meant: "sudo", other: "pseudo", sentence: "run the install with sudo"),
    ]

    /// Everyday pairs, the control the programmer pairs are compared against.
    public static let ordinaryPairs: [HomophonePair] = [
        HomophonePair(meant: "week", other: "weak", sentence: "we ship next week"),
        HomophonePair(meant: "piece", other: "peace", sentence: "take a piece of the cake"),
        HomophonePair(meant: "meet", other: "meat", sentence: "let us meet at noon"),
        HomophonePair(meant: "brake", other: "break", sentence: "press the brake pedal gently"),
        HomophonePair(meant: "sale", other: "sail", sentence: "the shoes are on sale today"),
        HomophonePair(meant: "whole", other: "hole", sentence: "i ate the whole pie"),
        HomophonePair(meant: "steel", other: "steal", sentence: "the beam is made of steel"),
        HomophonePair(meant: "plane", other: "plain", sentence: "the plane landed late"),
        HomophonePair(meant: "rode", other: "road", sentence: "she rode the bus home"),
        HomophonePair(meant: "buy", other: "by", sentence: "i will buy milk on the way"),
        HomophonePair(meant: "won", other: "one", sentence: "we won the match on sunday"),
        HomophonePair(meant: "hour", other: "our", sentence: "wait an hour please"),
        HomophonePair(meant: "know", other: "no", sentence: "i know the answer"),
        HomophonePair(meant: "here", other: "hear", sentence: "put the box down here"),
        HomophonePair(meant: "their", other: "there", sentence: "their car is parked outside"),
        HomophonePair(meant: "flour", other: "flower", sentence: "add a cup of flour to the bowl"),
        HomophonePair(meant: "pair", other: "pear", sentence: "she bought a pair of socks"),
        HomophonePair(meant: "mail", other: "male", sentence: "the mail came early today"),
        HomophonePair(meant: "tail", other: "tale", sentence: "the dog wagged its tail"),
        HomophonePair(meant: "write", other: "right", sentence: "please write your name here"),
    ]

    /// What the recogniser did with the meant word in one decode.
    public enum Outcome: Sendable, Equatable {
        /// It wrote the meant word, with this score.
        case right(score: Double)
        /// It wrote another word in its place, with this score.
        case wrong(heard: String, score: Double)
        /// It wrote nothing in its place.
        case dropped

        /// The score of whatever stands in the meant word's place; nil when nothing does.
        public var score: Double? {
            switch self {
            case .right(let score), .wrong(_, let score): score
            case .dropped: nil
            }
        }

        /// Whether the meant word failed to appear.
        public var isError: Bool {
            if case .right = self { false } else { true }
        }
    }

    /// Finds the reference word at `index` in the hypothesis by alignment, and reads its score.
    public static func outcome(
        reference: [String], index: Int, heard: [(word: String, score: Double)]
    ) -> Outcome {
        let alignment = WordErrorRate.measure(reference: reference, hypothesis: heard.map(\.word)).alignment
        var referenceIndex = 0
        var hypothesisIndex = 0
        for operation in alignment {
            switch operation {
            case .match, .substitution:
                if referenceIndex == index {
                    let found = heard[hypothesisIndex]
                    return found.word == reference[index]
                        ? .right(score: found.score) : .wrong(heard: found.word, score: found.score)
                }
                referenceIndex += 1
                hypothesisIndex += 1
            case .deletion:
                if referenceIndex == index { return .dropped }
                referenceIndex += 1
            case .insertion:
                hypothesisIndex += 1
            }
        }
        return .dropped
    }

    /// The statistics one row of the table reports.
    public struct Summary: Sendable, Equatable {
        /// Decodes counted.
        public let decodes: Int
        /// Decodes where the meant word did not appear.
        public let errors: Int
        /// Median score of the word written in a wrong decode; nil when no wrong decode had a word.
        public let medianWrongScore: Double?
        /// Share of wrong decodes the gate doubts, a dropped word counting as not doubted; nil with no errors.
        public let wrongBelowGate: Double?
        /// Share of right decodes the gate doubts; nil with no right decode.
        public let rightBelowGate: Double?
        /// Area under the ROC curve of the score as an error detector; nil without both outcomes scored.
        public let auc: Double?

        /// Errors over decodes.
        public var errorRate: Double { decodes == 0 ? 0 : Double(errors) / Double(decodes) }
    }

    /// The row for a set of outcomes.
    public static func summary(_ outcomes: [Outcome]) -> Summary {
        let wrongScores = outcomes.filter(\.isError).compactMap(\.score)
        let rightScores = outcomes.filter { !$0.isError }.compactMap(\.score)
        let errors = outcomes.count(where: \.isError)
        return Summary(
            decodes: outcomes.count,
            errors: errors,
            medianWrongScore: median(wrongScores),
            wrongBelowGate: errors == 0 ? nil : Double(wrongScores.count { $0 < gate }) / Double(errors),
            rightBelowGate: rightScores.isEmpty
                ? nil : Double(rightScores.count { $0 < gate }) / Double(rightScores.count),
            auc: auc(wrong: wrongScores, right: rightScores))
    }

    /// The middle value, or the mean of the two middle values; nil when empty.
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Chance a wrong word scores below a right one, ties counting half; 0.5 is no better than a coin.
    public static func auc(wrong: [Double], right: [Double]) -> Double? {
        guard !wrong.isEmpty, !right.isEmpty else { return nil }
        var wins = 0.0
        for low in wrong {
            for high in right {
                if low < high { wins += 1 } else if low == high { wins += 0.5 }
            }
        }
        return wins / Double(wrong.count * right.count)
    }
}
