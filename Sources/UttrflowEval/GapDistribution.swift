// The tables of the gap-distribution probe: each speaker's gaps, and break scores by rule.
private import Foundation

/// One speaker's dictations, each as the gaps read from its audio in the order heard.
public struct SpeakerGaps: Sendable, Equatable {
    public let profile: SpeakerProfile
    public let dictations: [[GapObservation]]

    public init(profile: SpeakerProfile, dictations: [[GapObservation]]) {
        self.profile = profile
        self.dictations = dictations
    }
}

public enum GapDistribution {
    /// The rule the issue's hypothesis compares against, and the rank rule decided before the run.
    public static let fixed = PauseRule.fixed(milliseconds: 700)
    public static let relative = PauseRule.relative(spreads: 3)

    /// Rules shown so the choice of the two above can be checked against its neighbours.
    static let swept: [PauseRule] = [
        .fixed(milliseconds: 400), .fixed(milliseconds: 500), fixed, .fixed(milliseconds: 1000),
        .relative(spreads: 2), relative, .relative(spreads: 4), .relative(spreads: 6),
    ]

    /// The value `fraction` of the way through `values`, by nearest rank; zero when empty.
    public static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
    }

    /// Gap lengths per speaker: the gaps between words and hesitations, and the breaks, in milliseconds.
    public static func distributionMarkdown(_ speakers: [SpeakerGaps]) -> String {
        let head = [
            "| Speaker | Dictations | Other gaps | Other median ms | Other 90th ms | Other longest ms | "
                + "Breaks | Break shortest ms | Break median ms |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        let rows = speakers.map { speaker -> String in
            let gaps = speaker.dictations.flatMap { $0 }
            let others = gaps.filter { !$0.isBreak }.map(\.milliseconds)
            let breaks = gaps.filter(\.isBreak).map(\.milliseconds)
            return "| \(speaker.profile.voice) \(speaker.profile.name) | \(speaker.dictations.count) | "
                + "\(others.count) | \(whole(PauseTiming.median(others))) | \(whole(percentile(others, 0.9))) | "
                + "\(whole(others.max() ?? 0)) | \(breaks.count) | \(whole(breaks.min() ?? 0)) | "
                + "\(whole(PauseTiming.median(breaks))) |"
        }
        return (head + rows).joined(separator: "\n")
    }

    /// Break F1 for each rule, by speaker pace and over all speakers.
    public static func scoreMarkdown(_ speakers: [SpeakerGaps]) -> String {
        let paces = orderedPaces(speakers)
        let head = [
            "| Rule | " + (paces + ["All"]).joined(separator: " | ") + " |",
            "|---|" + String(repeating: "---|", count: paces.count + 1),
        ]
        let rows = swept.map { rule -> String in
            let cells = paces.map { pace in
                f1(rule, speakers.filter { $0.profile.name == pace })
            }
            return "| \(label(rule)) | " + (cells + [f1(rule, speakers)]).joined(separator: " | ") + " |"
        }
        return (head + rows).joined(separator: "\n")
    }

    /// The change in each dictation's break F1 from the fixed rule to the rank rule, with its paired bound.
    public static func change(_ speakers: [SpeakerGaps]) -> PairedChange {
        let dictations = speakers.flatMap(\.dictations)
        return PairedChange(
            before: dictations.map { fixed.score($0).f1 }, after: dictations.map { relative.score($0).f1 })
    }

    static func label(_ rule: PauseRule) -> String {
        switch rule {
        case .fixed(let length): return "fixed \(whole(length)) ms"
        case .relative(let spreads): return "rank \(whole(spreads)) spreads"
        }
    }

    private static func orderedPaces(_ speakers: [SpeakerGaps]) -> [String] {
        var seen: [String] = []
        for name in speakers.map(\.profile.name) where !seen.contains(name) { seen.append(name) }
        return seen
    }

    private static func f1(_ rule: PauseRule, _ speakers: [SpeakerGaps]) -> String {
        let total = speakers.flatMap(\.dictations).reduce(BreakScore()) { $0 + rule.score($1) }
        return String(format: "%.2f", total.f1)
    }

    private static func whole(_ value: Double) -> String { String(format: "%.0f", value) }
}
