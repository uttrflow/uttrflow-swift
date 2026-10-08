// Whether the recogniser's word score means the same thing for every accent group.
private import Foundation

/// One reference word as the recogniser handled it: the group of the speaker, the score in its place, and whether it is right.
public struct GradedWord: Sendable, Equatable {
    /// The accent group of the voice or speaker.
    public let group: String
    /// The score of the word written in the reference word's place; nil when nothing was written there.
    public let score: Double?
    /// Whether the word written there is the reference word.
    public let isRight: Bool

    /// One aligned reference word.
    public init(group: String, score: Double?, isRight: Bool) {
        self.group = group
        self.score = score
        self.isRight = isRight
    }
}

/// Per-group reliability and the three shares the doubt gate turns on, with the groups that stand apart.
public enum GroupCalibration {
    /// Upper edges of the reliability bins; the last bin closes at 1.
    public static let binEdges = [0.2, 0.4, 0.5, 0.6, 0.8, 0.9, 1.0]

    /// One reliability bin: how many words scored in it and how many of those were right.
    public struct Bin: Sendable, Equatable {
        public let upper: Double
        public let words: Int
        public let right: Int

        public init(upper: Double, words: Int, right: Int) {
            self.upper = upper
            self.words = words
            self.right = right
        }
    }

    /// A share and its 95% Wilson interval.
    public struct Share: Sendable, Equatable {
        public let count: Int
        public let total: Int

        public init(count: Int, total: Int) {
            self.count = count
            self.total = total
        }

        public var value: Double { total == 0 ? 0 : Double(count) / Double(total) }
        /// The Wilson score interval at 95%.
        public var interval: ClosedRange<Double> {
            guard total > 0 else { return 0...1 }
            let z = 1.96
            let n = Double(total)
            let p = value
            let centre = (p + z * z / (2 * n)) / (1 + z * z / n)
            let half = z * ((p * (1 - p) / n + z * z / (4 * n * n)).squareRoot()) / (1 + z * z / n)
            return max(0, centre - half)...min(1, centre + half)
        }
    }

    /// One group's row.
    public struct Row: Sendable, Equatable {
        public let group: String
        public let words: Int
        public let errors: Int
        /// Errors the gate doubts: written below the threshold. A dropped word counts as not seen.
        public let seen: Share
        /// Errors written at or above the threshold, which no candidate source is ever asked about.
        public let confident: Share
        /// Right words written below the threshold, each one put at risk of replacement.
        public let falselyDoubted: Share
        public let bins: [Bin]
    }

    /// The rows, in the order the groups first appear.
    public static func rows(_ words: [GradedWord], threshold: Double) -> [Row] {
        var order: [String] = []
        var byGroup: [String: [GradedWord]] = [:]
        for word in words {
            if byGroup[word.group] == nil { order.append(word.group) }
            byGroup[word.group, default: []].append(word)
        }
        return order.map { row(group: $0, byGroup[$0] ?? [], threshold: threshold) }
    }

    static func row(group: String, _ words: [GradedWord], threshold: Double) -> Row {
        let errors = words.filter { !$0.isRight }
        let right = words.filter(\.isRight)
        let seen = errors.count { $0.score.map { $0 < threshold } ?? false }
        let confident = errors.count { $0.score.map { $0 >= threshold } ?? false }
        let doubted = right.count { $0.score.map { $0 < threshold } ?? false }
        let scored = words.compactMap { word in word.score.map { (score: $0, isRight: word.isRight) } }
        let bins = binEdges.map { upper in
            let inBin = scored.filter { binUpper(of: $0.score) == upper }
            return Bin(upper: upper, words: inBin.count, right: inBin.count(where: \.isRight))
        }
        return Row(
            group: group, words: words.count, errors: errors.count,
            seen: Share(count: seen, total: errors.count),
            confident: Share(count: confident, total: errors.count),
            falselyDoubted: Share(count: doubted, total: right.count), bins: bins)
    }

    /// The upper edge of the bin a score falls in: the first edge above it, a score of 1 in the last bin.
    static func binUpper(of score: Double) -> Double {
        binEdges.first { score < $0 } ?? 1.0
    }

    /// Groups whose seen share lies outside the best group's interval and whose own interval excludes the best share.
    public static func standingApart(_ rows: [Row]) -> [Row] {
        guard let best = rows.filter({ $0.errors > 0 }).max(by: { $0.seen.value < $1.seen.value }) else {
            return []
        }
        return rows.filter { row in
            row.group != best.group && row.errors > 0
                && !best.seen.interval.contains(row.seen.value)
                && !row.seen.interval.contains(best.seen.value)
        }
    }

    /// The per-group table and the reliability table, as Markdown.
    public static func markdown(_ rows: [Row]) -> String {
        func percent(_ share: Share) -> String {
            guard share.total > 0 else { return "n/a" }
            let range = share.interval
            return String(
                format: "%.1f%% (%.0f–%.0f)", share.value * 100, range.lowerBound * 100,
                range.upperBound * 100)
        }
        var lines = [
            "| Group | Words | Errors | Seen | Confident | Falsely doubted |",
            "|---|---|---|---|---|---|",
        ]
        for row in rows {
            lines.append(
                "| \(row.group) | \(row.words) | \(row.errors) | \(percent(row.seen)) | "
                    + "\(percent(row.confident)) | \(percent(row.falselyDoubted)) |")
        }
        lines.append("")
        let header = binEdges.map { String(format: "< %.1f", $0) }.joined(separator: " | ")
        lines.append("| Group | " + header.replacingOccurrences(of: "< 1.0", with: "≤ 1.0") + " |")
        lines.append("|---|" + String(repeating: "---|", count: binEdges.count))
        for row in rows {
            let cells = row.bins.map { bin in
                bin.words == 0
                    ? "–"
                    : String(format: "%.0f%% of %d", Double(bin.right) / Double(bin.words) * 100, bin.words)
            }
            lines.append("| \(row.group) | " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
