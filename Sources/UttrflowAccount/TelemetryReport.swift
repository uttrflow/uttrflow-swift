// The telemetry report: integers, dates and closed enumerations, the only shape that leaves the Mac.
public import UttrflowCore
public import struct Foundation.Date

public import struct Foundation.Data
public import class Foundation.JSONEncoder

/// A closed set of languages a report may name; any other is ``other``. See Docs/account-telemetry.md.
public enum TelemetryLanguage: String, Sendable, Equatable, CaseIterable, Codable {
    case arabic = "ar"
    case bengali = "bn"
    case chinese = "zh"
    case dutch = "nl"
    case english = "en"
    case french = "fr"
    case german = "de"
    case gujarati = "gu"
    case hebrew = "he"
    case hindi = "hi"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case marathi = "mr"
    case polish = "pl"
    case portuguese = "pt"
    case punjabi = "pa"
    case russian = "ru"
    case spanish = "es"
    case swedish = "sv"
    case tamil = "ta"
    case telugu = "te"
    case thai = "th"
    case turkish = "tr"
    case ukrainian = "uk"
    case urdu = "ur"
    case vietnamese = "vi"

    /// Anything not on the list; `und` is BCP-47's own "undetermined", so the server needs no special case.
    case other = "und"

    /// Narrows the app's language code to one on the list, or ``other``; lossy on purpose, in one line.
    public init(_ code: LanguageCode) {
        self = TelemetryLanguage(rawValue: code.value) ?? .other
    }
}

/// A pipeline stage spelled as the backend's `pipeline_stage` enumeration spells it.
public enum TelemetryStage: String, Sendable, Equatable, CaseIterable, Codable {
    case audioCapture = "audio-capture"
    case transcription
    case tidying
    case insertion

    /// `nil` for correction and expansion, which the server cannot name. See Docs/account-telemetry.md.
    public init?(_ stage: PipelineStage) {
        switch stage {
        case .capture: self = .audioCapture
        case .transcription: self = .transcription
        case .transformation: self = .tidying
        case .insertion: self = .insertion
        case .correction, .expansion: return nil
        }
    }
}

/// Everything Uttrflow ever sends about its use, with no `String` in it. See Docs/account-telemetry.md.
public struct TelemetryReport: Sendable, Equatable, Encodable {
    /// The app's version as three numbers, never as a string.
    public struct AppVersion: Sendable, Equatable, Encodable {
        /// The first number.
        public let major: Int
        /// The second number.
        public let minor: Int
        /// The third number.
        public let patch: Int

        /// Clamps each part to the server's `versionPart` of 0...999; anything else is a 400.
        public init(major: Int, minor: Int, patch: Int) {
            self.major = TelemetryLimit.versionPart.clamping(major)
            self.minor = TelemetryLimit.versionPart.clamping(minor)
            self.patch = TelemetryLimit.versionPart.clamping(patch)
        }
    }

    /// How many dictations one language had.
    public struct LanguageCount: Sendable, Equatable, Encodable {
        /// The language.
        public let language: TelemetryLanguage
        /// How many dictations were in it, clamped to the server's `count`.
        public let dictationCount: Int

        /// Clamps the count into the server's range.
        public init(language: TelemetryLanguage, dictationCount: Int) {
            self.language = language
            self.dictationCount = TelemetryLimit.count.clamping(dictationCount)
        }
    }

    /// How one stage fared: how often it failed, and how slow it ran when it did not.
    public struct StageOutcome: Sendable, Equatable, Encodable {
        /// The stage.
        public let stage: TelemetryStage
        /// How many times it failed.
        public let failureCount: Int
        /// Median latency in milliseconds, or `nil` when nothing timed it.
        public let latencyP50Ms: Int?
        /// Ninetieth-percentile latency, never below the median.
        public let latencyP90Ms: Int?

        /// Clamps the count and latencies, raising the ninetieth percentile to the median when below it.
        public init(stage: TelemetryStage, failureCount: Int, latencyP50Ms: Int?, latencyP90Ms: Int?) {
            self.stage = stage
            self.failureCount = TelemetryLimit.count.clamping(failureCount)
            self.latencyP50Ms = TelemetryLimit.latency(latencyP50Ms)
            self.latencyP90Ms = TelemetryLimit.latency(latencyP90Ms, notBelow: self.latencyP50Ms)
        }
    }

    /// When the summarised period opened; a period, not an event, so no sentence is timestamped.
    public let windowStartedAt: Date
    /// When the summarised period closed.
    public let windowEndedAt: Date
    /// This build.
    public let appVersion: AppVersion
    /// The macOS major version, or `nil` when the app has not been told what it runs on.
    public let osVersionMajor: Int?

    /// How many dictations started in the window.
    public let dictationCount: Int
    /// How many the user abandoned; never more than `dictationCount`.
    public let cancelledCount: Int
    /// How many failed outright.
    public let failureCount: Int
    /// How long the microphone was open in total.
    public let audioTotalMs: Int
    /// How long the user waited in total.
    public let processingTotalMs: Int
    /// A count of characters inserted, not the characters.
    public let charactersInserted: Int

    /// Median end-to-end latency, or `nil` when nothing was measured.
    public let latencyP50Ms: Int?
    /// Ninetieth percentile, never below the median.
    public let latencyP90Ms: Int?
    /// Ninety-ninth percentile, never below the ninetieth.
    public let latencyP99Ms: Int?

    /// Sorted by tag and deduplicated, so the same report encodes to the same bytes, within the server's cap.
    public let languages: [LanguageCount]
    /// One entry per stage at most, sorted by name.
    public let stages: [StageOutcome]

    /// Builds a report, or `nil` when the window did not advance or held no dictation; numbers are clamped.
    public init?(
        windowStartedAt: Date,
        windowEndedAt: Date,
        appVersion: AppVersion,
        osVersionMajor: Int? = nil,
        dictationCount: Int,
        cancelledCount: Int = 0,
        failureCount: Int = 0,
        audioTotalMs: Int = 0,
        processingTotalMs: Int = 0,
        charactersInserted: Int = 0,
        latencyP50Ms: Int? = nil,
        latencyP90Ms: Int? = nil,
        latencyP99Ms: Int? = nil,
        languages: [TelemetryLanguage: Int] = [:],
        stages: [StageOutcome] = []
    ) {
        let dictations = TelemetryLimit.count.clamping(dictationCount)
        guard windowEndedAt > windowStartedAt, dictations > 0 else { return nil }

        self.windowStartedAt = windowStartedAt
        self.windowEndedAt = windowEndedAt
        self.appVersion = appVersion
        self.osVersionMajor = osVersionMajor.map(TelemetryLimit.versionPart.clamping)
        self.dictationCount = dictations
        self.cancelledCount = min(TelemetryLimit.count.clamping(cancelledCount), dictations)
        self.failureCount = TelemetryLimit.count.clamping(failureCount)
        self.audioTotalMs = TelemetryLimit.durationMs.clamping(audioTotalMs)
        self.processingTotalMs = TelemetryLimit.durationMs.clamping(processingTotalMs)
        self.charactersInserted = TelemetryLimit.count.clamping(charactersInserted)

        self.latencyP50Ms = TelemetryLimit.latency(latencyP50Ms)
        self.latencyP90Ms = TelemetryLimit.latency(latencyP90Ms, notBelow: self.latencyP50Ms)
        self.latencyP99Ms = TelemetryLimit.latency(
            latencyP99Ms, notBelow: self.latencyP90Ms ?? self.latencyP50Ms)

        // A dictionary in, a sorted array out: no duplicate keys, and the same bytes for the same numbers.
        self.languages =
            languages
            .filter { $0.value > 0 }
            .map { LanguageCount(language: $0.key, dictationCount: $0.value) }
            .sorted { $0.language.rawValue < $1.language.rawValue }
        self.stages =
            Dictionary(stages.map { ($0.stage, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.stage.rawValue < $1.stage.rawValue }
    }

    /// The keys the backend's `.strict()` Zod schema declares; a key it has not heard of is a 400.
    private enum CodingKeys: String, CodingKey {
        case windowStartedAt, windowEndedAt, appVersion, osVersionMajor
        case dictationCount, cancelledCount, failureCount
        case audioTotalMs, processingTotalMs, charactersInserted
        case latencyP50Ms, latencyP90Ms, latencyP99Ms
        case languages, stages
    }

    /// Written by hand so what leaves the Mac is one readable function; optionals are omitted, never `null`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Formatted here rather than by the encoder's date strategy, which sends a number and is refused.
        try container.encode(windowStartedAt.formatted(.iso8601), forKey: .windowStartedAt)
        try container.encode(windowEndedAt.formatted(.iso8601), forKey: .windowEndedAt)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(osVersionMajor, forKey: .osVersionMajor)
        try container.encode(dictationCount, forKey: .dictationCount)
        try container.encode(cancelledCount, forKey: .cancelledCount)
        try container.encode(failureCount, forKey: .failureCount)
        try container.encode(audioTotalMs, forKey: .audioTotalMs)
        try container.encode(processingTotalMs, forKey: .processingTotalMs)
        try container.encode(charactersInserted, forKey: .charactersInserted)
        try container.encodeIfPresent(latencyP50Ms, forKey: .latencyP50Ms)
        try container.encodeIfPresent(latencyP90Ms, forKey: .latencyP90Ms)
        try container.encodeIfPresent(latencyP99Ms, forKey: .latencyP99Ms)
        try container.encode(languages, forKey: .languages)
        try container.encode(stages, forKey: .stages)
    }

    /// The exact bytes a sender puts on the wire, so the settings page and the upload show the same thing.
    public func encodedForIngest() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

/// The ranges the backend accepts, named once so the four types enforcing them cannot drift apart.
enum TelemetryLimit {
    /// The server's `count`: a non-negative 32-bit integer.
    static let count = 0...2_147_483_647
    /// The server's `durationMs`: up to a week, which no honest measurement reaches.
    static let durationMs = 0...604_800_000
    /// The server's `versionPart`.
    static let versionPart = 0...999

    /// A latency percentile the table accepts: clamped, and never below the percentile under it.
    static func latency(_ milliseconds: Int?, notBelow floor: Int? = nil) -> Int? {
        milliseconds.map { Swift.max(durationMs.clamping($0), floor ?? 0) }
    }
}

extension ClosedRange where Bound == Int {
    /// `value` brought inside the range; qualified because `ClosedRange` has `min()` and `max()` of its own.
    func clamping(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
