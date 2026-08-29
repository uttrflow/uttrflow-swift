public import UttrflowCore
public import struct Foundation.Date

public import struct Foundation.Data
public import class Foundation.JSONEncoder

/// A language Uttrflow will admit to having heard.
///
/// A closed set rather than a tag the caller supplies, and that is the whole reason it
/// exists. ``LanguageCode`` is the right type everywhere else in the app, but it wraps a
/// `String`, and a `String` on a type that gets uploaded is a place a transcript can go —
/// if not today then in two years, by somebody who needed "just a bit more context". The
/// narrowing happens once, at ``init(_:)``, and after it there is no free text anywhere in
/// this report.
///
/// Every raw value is a BCP-47 primary subtag matching the pattern the backend's
/// `language_tag` domain enforces, so a value that exists here cannot be one the server
/// refuses. Unrecognised languages become ``other`` rather than being passed through: an
/// unusual tag is itself identifying, and the product question — "which languages do
/// people dictate in" — is answered just as well by knowing that this one was not on the
/// list.
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

    /// Anything not on the list. `und` is BCP-47's own "undetermined", so the server needs
    /// no special case for it.
    case other = "und"

    /// Narrows the app's language code to something safe to upload.
    ///
    /// Lossy on purpose, and lossy in one line: a table mapping each language by hand
    /// would be a table somebody could add a passthrough to.
    public init(_ code: LanguageCode) {
        self = TelemetryLanguage(rawValue: code.value) ?? .other
    }
}

/// A stage of the pipeline, named the way the backend's `pipeline_stage` enumeration
/// names it.
///
/// Separate from ``PipelineStage`` because the two vocabularies genuinely differ — the
/// server has stages this app does not measure, and spells two of the shared ones
/// differently. Mapping in a total `switch` rather than by string manipulation means a
/// stage added to the pipeline is a compile error here, which is the moment to decide
/// whether it should be reported at all.
public enum TelemetryStage: String, Sendable, Equatable, CaseIterable, Codable {
    case audioCapture = "audio-capture"
    case transcription
    case tidying
    case insertion

    /// `nil` for a stage the server's `pipeline_stage` enumeration has no name for.
    ///
    /// Correction and expansion are measured on the Mac and reported on the diagnostics
    /// page, but the backend's column is a closed domain and `migrations/0005_telemetry`
    /// is not this repository's to widen: inventing a value here would turn every report
    /// from a user with a dictionary into a 400. Declining to send them costs no total —
    /// `processingTotalMs` still times the whole journey — and the day the column gains
    /// the two names, this is the one place that has to change.
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

/// Everything Uttrflow ever sends about how it is being used, and nothing else.
///
/// The list of stored properties below is the complete, exhaustive answer to "what leaves
/// my Mac". Read it: every one is an `Int`, a `Date`, or a value of a closed enumeration.
/// There is no `String` on this type, none on any type it contains, and none reachable
/// through either — so there is nowhere to put a transcript, a window title, an
/// application name or a dictionary entry, and no reviewer has to take anyone's word for
/// it. `TelemetryPrivacyTests` says the same thing in a test, and the backend's
/// `migrations/0005_telemetry.sql` says it a third time in the columns.
///
/// The dates are the exception that proves it: a `Date` is a number of seconds, and the
/// ISO-8601 string the server wants is produced during encoding rather than stored, so
/// there is still no text a caller could reach.
///
/// Ranges are enforced in ``init(windowStartedAt:windowEndedAt:appVersion:osVersionMajor:dictationCount:cancelledCount:failureCount:audioTotalMs:processingTotalMs:charactersInserted:latencyP50Ms:latencyP90Ms:latencyP99Ms:languages:stages:)``
/// rather than checked at the door, because the backend's schema is `.strict()` and its
/// table has `check` constraints: an out-of-range number is a 400 or a 500, and a report
/// that cannot be sent is worse than one that has been rounded into shape.
public struct TelemetryReport: Sendable, Equatable, Encodable {
    /// The app's version, as three numbers.
    ///
    /// Not `"1.2.3"`. A version string is a `String`, and this type has none.
    public struct AppVersion: Sendable, Equatable, Encodable {
        public let major: Int
        public let minor: Int
        public let patch: Int

        /// Clamped to the server's `versionPart` of 0...999; anything else is a 400.
        public init(major: Int, minor: Int, patch: Int) {
            self.major = TelemetryLimit.versionPart.clamping(major)
            self.minor = TelemetryLimit.versionPart.clamping(minor)
            self.patch = TelemetryLimit.versionPart.clamping(patch)
        }
    }

    /// How many dictations were in one language.
    public struct LanguageCount: Sendable, Equatable, Encodable {
        public let language: TelemetryLanguage
        public let dictationCount: Int

        public init(language: TelemetryLanguage, dictationCount: Int) {
            self.language = language
            self.dictationCount = TelemetryLimit.count.clamping(dictationCount)
        }
    }

    /// How one stage fared: how often it failed, and how slow it was when it did not.
    public struct StageOutcome: Sendable, Equatable, Encodable {
        public let stage: TelemetryStage
        public let failureCount: Int
        public let latencyP50Ms: Int?
        public let latencyP90Ms: Int?

        public init(stage: TelemetryStage, failureCount: Int, latencyP50Ms: Int?, latencyP90Ms: Int?) {
            self.stage = stage
            self.failureCount = TelemetryLimit.count.clamping(failureCount)
            let median = latencyP50Ms.map(TelemetryLimit.durationMs.clamping)
            self.latencyP50Ms = median
            // The table refuses a p90 below its p50, and a refused report is data lost for
            // everyone rather than a wrong number for one stage.
            self.latencyP90Ms = latencyP90Ms.map { max(TelemetryLimit.durationMs.clamping($0), median ?? 0) }
        }
    }

    /// The period being summarised. Periods rather than events, so no timestamp here is
    /// precise enough to say when any particular sentence was dictated.
    public let windowStartedAt: Date
    public let windowEndedAt: Date
    public let appVersion: AppVersion
    /// The macOS major version. `nil` when the app has not been told what it is running on.
    public let osVersionMajor: Int?

    public let dictationCount: Int
    public let cancelledCount: Int
    public let failureCount: Int
    /// How long the microphone was open in total.
    public let audioTotalMs: Int
    /// How long the user waited in total.
    public let processingTotalMs: Int
    /// A count of characters inserted. Not the characters.
    public let charactersInserted: Int

    public let latencyP50Ms: Int?
    public let latencyP90Ms: Int?
    public let latencyP99Ms: Int?

    /// Sorted by tag and deduplicated, so the same report always encodes to the same bytes
    /// and cannot exceed the server's limit of sixty-four entries.
    public let languages: [LanguageCount]
    /// One entry per stage at most, in the order the journey runs.
    public let stages: [StageOutcome]

    /// Builds a report, or refuses.
    ///
    /// Fails when the window did not advance or when nothing happened in it. Both are
    /// refusals rather than fixes: the table requires `window_ended_at > window_started_at`,
    /// and a report of no dictations is a request that costs the user's battery to tell the
    /// server nothing.
    ///
    /// - Parameters:
    ///   - windowStartedAt: When the app started counting.
    ///   - windowEndedAt: When it stopped. Must be later than `windowStartedAt`.
    ///   - appVersion: This build.
    ///   - osVersionMajor: The macOS major version, if known.
    ///   - dictationCount: How many dictations were started. Must be more than none.
    ///   - cancelledCount: How many the user abandoned. Clamped to `dictationCount`,
    ///     which the table also insists on.
    ///   - failureCount: How many failed outright.
    ///   - audioTotalMs: Total milliseconds the microphone was open.
    ///   - processingTotalMs: Total milliseconds the user spent waiting.
    ///   - charactersInserted: How many characters were inserted, not which.
    ///   - latencyP50Ms: Median end-to-end latency, if anything was measured.
    ///   - latencyP90Ms: Ninetieth percentile, raised to the median if it fell below it.
    ///   - latencyP99Ms: Ninety-ninth percentile, raised to the ninetieth likewise.
    ///   - languages: How many dictations in each language.
    ///   - stages: How each stage fared.
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

        // Percentiles that go backwards fail the table's `check` and cost the whole report.
        let median = latencyP50Ms.map(TelemetryLimit.durationMs.clamping)
        let ninetieth = latencyP90Ms.map { max(TelemetryLimit.durationMs.clamping($0), median ?? 0) }
        self.latencyP50Ms = median
        self.latencyP90Ms = ninetieth
        self.latencyP99Ms = latencyP99Ms.map {
            max(TelemetryLimit.durationMs.clamping($0), ninetieth ?? median ?? 0)
        }

        // A dictionary in, a sorted array out: duplicate keys are impossible rather than
        // merged, and the encoded bytes are the same every time for the same numbers.
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

    /// The keys the backend's Zod schema declares, and no others.
    ///
    /// The schema is `.strict()`, so a key it has not heard of is a 400 rather than a
    /// field it quietly drops. That is the behaviour we want and this is the list that has
    /// to match it.
    private enum CodingKeys: String, CodingKey {
        case windowStartedAt, windowEndedAt, appVersion, osVersionMajor
        case dictationCount, cancelledCount, failureCount
        case audioTotalMs, processingTotalMs, charactersInserted
        case latencyP50Ms, latencyP90Ms, latencyP99Ms
        case languages, stages
    }

    /// Written out by hand so that the complete set of things that leave the Mac is one
    /// function somebody can read in ten seconds.
    ///
    /// The optionals use `encodeIfPresent` rather than encoding `null`, because the
    /// server's fields are `.optional()` and Zod refuses an explicit `null` for those.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Formatted here rather than left to the encoder's date strategy: a caller with a
        // differently configured encoder would send a number and be refused.
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

    /// The exact bytes a sender puts on the wire.
    ///
    /// Provided rather than left to the caller so there is one answer to "what did we
    /// send", and so the settings page showing the user their own reports and the sender
    /// uploading them are looking at the same thing.
    ///
    /// Optional rather than throwing, and with no fabricated fallback, for the reason
    /// ``UserDefaultsProfileCache/save(_:)`` gives: a value of integers, dates and closed
    /// enumerations has nothing in it that can fail to encode, so there is no second
    /// failure worth describing and nothing a caller could usefully do about it. Handing
    /// back the empty document instead would be inventing bytes nobody asked for.
    public func encodedForIngest() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

/// The ranges the backend accepts, in one place.
///
/// Named rather than written as literals at each use, because the same three ranges are
/// enforced in four types and a copy that drifts is a 400 nobody sees until the reports
/// stop arriving.
enum TelemetryLimit {
    /// The server's `count`: a non-negative 32-bit integer.
    static let count = 0...2_147_483_647
    /// The server's `durationMs`: up to a week, which no honest measurement reaches.
    static let durationMs = 0...604_800_000
    /// The server's `versionPart`.
    static let versionPart = 0...999
}

extension ClosedRange where Bound == Int {
    /// `value`, brought inside the range.
    ///
    /// Qualified, because `ClosedRange` has `min()` and `max()` of its own and the
    /// unqualified names would mean something else entirely here.
    func clamping(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
