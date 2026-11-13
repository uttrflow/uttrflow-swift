// Scores the language a recogniser detected against the language of each clip's reading, by clip length.

/// The clip lengths language identification is scored by, since a short piece carries the least evidence.
public enum ClipLengthBucket: String, CaseIterable, Sendable {
    case underOne = "under 1 s"
    case oneToTwo = "1-2 s"
    case twoToFive = "2-5 s"
    case overFive = "over 5 s"

    /// The bucket a clip of `seconds` falls in; a clip of exactly five seconds is in `twoToFive`.
    public init(seconds: Double) {
        switch seconds {
        case ..<1: self = .underOne
        case ..<2: self = .oneToTwo
        case ...5: self = .twoToFive
        default: self = .overFive
        }
    }
}

/// One clip: its reading group, the language that group means, and the recogniser's detection.
public struct LanguageIdentification: Sendable, Equatable {
    /// The reading of the clip, such as "en, en-IN voice" or "hi+en"; one row of the matrix per group.
    public let group: String
    /// The language code the clip should be detected as.
    public let expected: String
    /// The language code the recogniser detected, or `nil` when it reported none.
    public let detected: String?
    /// The recogniser's probability for its detection, or `nil` when it reported none.
    public let probability: Double?
    /// The clip's length in seconds.
    public let seconds: Double

    public init(group: String, expected: String, detected: String?, probability: Double?, seconds: Double) {
        self.group = group
        self.expected = expected
        self.detected = detected
        self.probability = probability
        self.seconds = seconds
    }

    /// Whether the detection matches the language of the reading; no detection is a miss.
    public var isRight: Bool { detected == expected }
}

/// Clips grouped by length and reading, with the detected language and the recogniser confidence per group.
public struct LanguageIdentificationMatrix: Sendable {
    /// The error rate above which a cell is reported on its own.
    public static let errorLimit = 0.05

    /// One length bucket of one reading group.
    public struct Cell: Sendable, Equatable {
        public let bucket: ClipLengthBucket
        public let group: String
        public let clips: Int
        public let wrong: Int
        /// How many clips were detected as each language; "none" counts clips with no detection.
        public let detected: [String: Int]
        /// The mean reported probability of each detected language, over the clips that reported one.
        public let meanProbability: [String: Double]

        /// The share of clips detected as anything but the language they were read in.
        public var errorRate: Double { clips == 0 ? 0 : Double(wrong) / Double(clips) }
    }

    public let cells: [Cell]

    public init(_ rows: [LanguageIdentification]) {
        let groups = rows.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        cells = groups.flatMap { group in
            ClipLengthBucket.allCases.compactMap { bucket -> Cell? in
                let clips = rows.filter {
                    $0.group == group && ClipLengthBucket(seconds: $0.seconds) == bucket
                }
                guard !clips.isEmpty else { return nil }
                let byLanguage = Dictionary(grouping: clips) { $0.detected ?? "none" }
                return Cell(
                    bucket: bucket, group: group, clips: clips.count,
                    wrong: clips.filter { !$0.isRight }.count,
                    detected: byLanguage.mapValues(\.count),
                    meanProbability: byLanguage.compactMapValues { detections in
                        let reported = detections.compactMap(\.probability)
                        return reported.isEmpty ? nil : reported.reduce(0, +) / Double(reported.count)
                    })
            }
        }
    }

    /// The cells whose error rate is above ``errorLimit``, each worth its own issue.
    public var cellsOverLimit: [Cell] { cells.filter { $0.errorRate > Self.errorLimit } }

    /// One table row per cell: its clips, its misses, and each detected language with its mean probability.
    public var markdown: String {
        var lines = [
            "| Read as | Length | Clips | Wrong | Error | Detected as (clips, mean p) |",
            "|---|---|---|---|---|---|",
        ]
        for cell in cells {
            let detected = cell.detected.keys.sorted().map { language in
                let mean = cell.meanProbability[language].map { String(format: "%.2f", $0) } ?? "n/a"
                return "\(language) (\(cell.detected[language] ?? 0), \(mean))"
            }
            let error = String(format: "%.1f%%", cell.errorRate * 100)
            lines.append(
                "| \(cell.group) | \(cell.bucket.rawValue) | \(cell.clips) | \(cell.wrong) | \(error) | "
                    + "\(detected.joined(separator: ", ")) |")
        }
        return lines.joined(separator: "\n")
    }
}
