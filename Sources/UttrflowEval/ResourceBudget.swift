// Judges memory and disk readings against the budget in Docs/performance.md.
public import UttrflowCore

/// A moment the memory budget names a limit for.
public enum BudgetedState: String, Sendable, Equatable, CaseIterable {
    /// The app idle with suggestions off, the speech model loaded.
    case idleSuggestionsOff
    /// The highest footprint during a dictation, suggestions off.
    case dictationPeak
    /// Suggestions on, between one pass and the next.
    case suggestionsBetweenPasses
    /// Suggestions on, the highest footprint inside a pass.
    case suggestionsPassPeak
    /// A second after the suggestion model is released, which must be back on the idle line.
    case afterRelease

    /// The most footprint this state may hold, in megabytes, as the budget table in Docs/performance.md states it.
    public var limitInMegabytes: Int64 {
        switch self {
        case .idleSuggestionsOff: return 300
        case .dictationPeak: return 400
        case .suggestionsBetweenPasses: return 3_072
        case .suggestionsPassPeak: return 3_584
        case .afterRelease: return BudgetedState.idleSuggestionsOff.limitInMegabytes
        }
    }

    /// The limit in bytes.
    public var limitInBytes: Int64 { limitInMegabytes * 1_048_576 }
}

/// One footprint reading taken in a budgeted state, with the label a report prints beside it.
public struct BudgetReading: Sendable, Equatable {
    public let state: BudgetedState
    public let label: String
    public let footprintBytes: Int64

    public init(state: BudgetedState, label: String, footprintBytes: Int64) {
        self.state = state
        self.label = label
        self.footprintBytes = footprintBytes
    }

    /// Whether the reading is over its state's limit, the one test both the judge and a report use.
    public var isOverBudget: Bool { footprintBytes > state.limitInBytes }
}

/// A reading over its state's limit.
public struct BudgetBreach: Sendable, Equatable, CustomStringConvertible {
    public let reading: BudgetReading

    /// How far over the limit the reading is, in bytes.
    public var excessBytes: Int64 { reading.footprintBytes - reading.state.limitInBytes }

    public var description: String {
        let megabytes = reading.footprintBytes / 1_048_576
        return
            "\(reading.label): \(megabytes) MB footprint, over the \(reading.state.limitInMegabytes) MB budget for \(reading.state.rawValue)"
    }
}

/// The memory budget as a judge: readings in, breaches out, so a harness fails rather than prints.
public enum ResourceBudget {
    /// Every reading over its state's limit, in the order they were taken.
    public static func breaches(in readings: [BudgetReading]) -> [BudgetBreach] {
        readings.filter(\.isOverBudget).map(BudgetBreach.init)
    }
}

extension ResourceBudget {
    /// A dictation profile's readings: every named moment is idle with suggestions off, and its peak is a dictation's.
    public static func readings(of timeline: MemoryTimeline) -> [BudgetReading] {
        let settled = timeline.samples.map {
            BudgetReading(
                state: .idleSuggestionsOff, label: $0.label, footprintBytes: $0.reading.footprintBytes)
        }
        let peak = timeline.peak.map {
            BudgetReading(
                state: .dictationPeak, label: "peak, mid-dictation", footprintBytes: $0.footprintBytes)
        }
        return settled + (peak.map { [$0] } ?? [])
    }
}

/// A part of the app's support folder the disk budget names a line for.
public enum DiskPart: String, Sendable, Equatable, CaseIterable {
    /// The installed speech model, with any staged download or superseded revision beside it.
    case speechModel
    /// Recordings waiting for a retry.
    case recordings
    /// The dictation history.
    case history
    /// The clipboard's list, its saved clips, its preferences and its pictures.
    case clipboard
    /// What the app keeps only to explain itself: the speech model's load times and the network ledger.
    case diagnostics
    /// Every other store: the dictionary, snippets, predictions, consent, the key and the lock.
    case otherStores

    /// The most this part may hold on disk, in megabytes, as the budget table in Docs/performance.md states it.
    public var limitInMegabytes: Int64 {
        switch self {
        case .speechModel: return 768
        case .recordings: return 256
        case .history: return 64
        case .clipboard: return 1_024
        case .diagnostics: return 16
        case .otherStores: return 64
        }
    }

    /// The limit in bytes.
    public var limitInBytes: Int64 { limitInMegabytes * 1_048_576 }

    /// The part a store entry counts against; exhaustive, so a new entry cannot go unbudgeted.
    public init(_ entry: LocalStoreEntry) {
        switch entry {
        case .speechModels: self = .speechModel
        case .recordings: self = .recordings
        case .dictationHistory: self = .history
        case .clipboard, .clipboardPreferences, .clipboardImages, .savedClips: self = .clipboard
        case .speechModelLoads, .networkActivity: self = .diagnostics
        case .personalDictionary, .snippets, .evidenceLedger, .predict, .predictConsent, .encryptionKey,
            .legacyMigrationMarker, .instanceLock:
            self = .otherStores
        }
    }
}

/// What one part of the support folder holds on disk.
public struct DiskReading: Sendable, Equatable, CustomStringConvertible {
    public let part: DiskPart
    public let bytes: Int64

    public init(part: DiskPart, bytes: Int64) {
        self.part = part
        self.bytes = bytes
    }

    /// Whether the part is over its line, the one test both the judge and a report use.
    public var isOverBudget: Bool { bytes > part.limitInBytes }

    public var description: String {
        "\(part.rawValue): \(bytes / 1_048_576) MB on disk, over the \(part.limitInMegabytes) MB budget"
    }
}

extension ResourceBudget {
    /// One reading per part, summing the store entries that count against it.
    public static func diskReadings(of usage: [LocalStoreUsage]) -> [DiskReading] {
        let totals = Dictionary(grouping: usage) { DiskPart($0.entry) }.mapValues {
            $0.reduce(Int64(0)) { $0 + $1.bytes }
        }
        return DiskPart.allCases.map { DiskReading(part: $0, bytes: totals[$0] ?? 0) }
    }

    /// Every part over its line, in the budget table's order.
    public static func breaches(in readings: [DiskReading]) -> [DiskReading] {
        readings.filter(\.isOverBudget)
    }
}
