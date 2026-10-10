// The speech model's last loads, kept so a slow first dictation after an update can be explained later.
public import struct Foundation.Date

/// What set a load apart from the load before it, which says whether a slow one was to be expected.
public enum SpeechModelLoadChange: String, Codable, Sendable, CaseIterable {
    /// No earlier load is kept, so the model may never have been compiled for this Mac.
    case firstRecorded
    /// Same macOS build and same model revision as the load before.
    case unchanged
    /// macOS changed build since the load before, which discards the system's compiled copy.
    case systemUpdated
    /// The model's revision changed since the load before, so there was nothing compiled to reuse.
    case modelChanged

    /// Whether the system had a reason to compile the model again, which makes a slow load expected.
    public var expectsSlowLoad: Bool { self != .unchanged }
}

/// Where one load's seconds went, as the recogniser measured its own parts.
public struct SpeechModelLoadParts: Codable, Sendable, Equatable {
    public let prewarm: Double
    public let specialiseEncoder: Double
    public let specialiseDecoder: Double
    public let loadEncoder: Double
    public let loadDecoder: Double
    public let tokenizer: Double

    public init(
        prewarm: Double, specialiseEncoder: Double, specialiseDecoder: Double, loadEncoder: Double,
        loadDecoder: Double, tokenizer: Double
    ) {
        self.prewarm = prewarm
        self.specialiseEncoder = specialiseEncoder
        self.specialiseDecoder = specialiseDecoder
        self.loadEncoder = loadEncoder
        self.loadDecoder = loadDecoder
        self.tokenizer = tokenizer
    }
}

/// One finished load of the speech model: when, how long, and what was different about it.
public struct SpeechModelLoadRecord: Codable, Sendable, Equatable {
    public let date: Date
    public let seconds: Double
    /// Absent when the recogniser did not report its parts.
    public let parts: SpeechModelLoadParts?
    /// The macOS build, such as "25F71", which changes with every system update.
    public let systemBuild: String
    public let modelRevision: String
    public let change: SpeechModelLoadChange
    /// Took more than ``SpeechModelLoadHistory/recompileFactor`` times the median of the loads before it.
    public let isLikelyRecompile: Bool

    public init(
        date: Date, seconds: Double, parts: SpeechModelLoadParts?, systemBuild: String,
        modelRevision: String, change: SpeechModelLoadChange, isLikelyRecompile: Bool
    ) {
        self.date = date
        self.seconds = seconds
        self.parts = parts
        self.systemBuild = systemBuild
        self.modelRevision = modelRevision
        self.change = change
        self.isLikelyRecompile = isLikelyRecompile
    }
}

/// The last few loads, oldest first, each judged against the ones before it as it is added.
public struct SpeechModelLoadHistory: Codable, Sendable, Equatable {
    /// How many loads are kept.
    public static let capacity = 10
    /// How many times the median of earlier loads a load must take to be called a likely recompile.
    public static let recompileFactor = 5.0

    public private(set) var records: [SpeechModelLoadRecord]

    public init(records: [SpeechModelLoadRecord] = []) {
        self.records = Array(records.suffix(Self.capacity))
    }

    /// What a load on this macOS build and model revision would differ by from the last one kept.
    public func change(systemBuild: String, modelRevision: String) -> SpeechModelLoadChange {
        guard let last = records.last else { return .firstRecorded }
        if last.modelRevision != modelRevision { return .modelChanged }
        if last.systemBuild != systemBuild { return .systemUpdated }
        return .unchanged
    }

    /// The median seconds of the loads kept, or `nil` when none is.
    public var medianSeconds: Double? {
        let sorted = records.map(\.seconds).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Adds a finished load, judged against the loads before it, dropping the oldest past ``capacity``.
    @discardableResult
    public mutating func append(
        date: Date, seconds: Double, parts: SpeechModelLoadParts?, systemBuild: String,
        modelRevision: String
    ) -> SpeechModelLoadRecord {
        let record = SpeechModelLoadRecord(
            date: date, seconds: seconds, parts: parts, systemBuild: systemBuild,
            modelRevision: modelRevision,
            change: change(systemBuild: systemBuild, modelRevision: modelRevision),
            isLikelyRecompile: medianSeconds.map { seconds > $0 * Self.recompileFactor } ?? false)
        records = Array((records + [record]).suffix(Self.capacity))
        return record
    }
}
