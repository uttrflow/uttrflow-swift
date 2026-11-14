// A small on-device ledger of closed counters about how dictation goes; it holds no text and is never sent.

public import Foundation
import UttrflowCore

/// How one dictation ended.
public enum UXOutcome: String, Codable, Sendable, CaseIterable {
    case inserted, copied, cancelled, failed
}

/// How long text took to land after the key was released.
public enum UXLanding: String, Codable, Sendable, CaseIterable {
    case under250ms, under500ms, under1s, under2s, over2s

    /// The bucket a time from key release to words falls in.
    public init(milliseconds: Int) {
        switch milliseconds {
        case ..<250: self = .under250ms
        case ..<500: self = .under500ms
        case ..<1_000: self = .under1s
        case ..<2_000: self = .under2s
        default: self = .over2s
        }
    }
}

/// One thing that happened, with no words in it. See `Docs/ux-measurement.md`.
public enum UXEvent: Sendable, Equatable {
    /// The dictation key went down to begin one.
    case started
    case ended(UXOutcome)
    /// The person took back a dictation.
    case undone
    /// Text landed this many milliseconds after the key was released.
    case landed(milliseconds: Int)
    /// The onboarding page with this number was shown.
    case onboardingPage(Int)
}

/// The counters for one calendar day; integers only.
public struct UXDay: Codable, Sendable, Equatable {
    /// Whole days since the reference date, in the current calendar.
    public let number: Int
    public var started = 0
    public var outcomes: [UXOutcome: Int] = [:]
    /// Starts that came within the retry window of a cancelled or failed dictation.
    public var retries = 0
    public var undos = 0
    public var landings: [UXLanding: Int] = [:]

    public init(number: Int) { self.number = number }
}

/// The ledger: install date, first-use times and the last thirty days of counters.
public struct UXLedger: Codable, Sendable, Equatable {
    /// The days the ledger keeps.
    public static let daysKept = 30
    /// A start within this long of a cancelled or failed dictation is a retry, not a new attempt.
    public static let retryWindow: TimeInterval = 60

    public private(set) var installedOn: Date
    public private(set) var firstPress: Date?
    public private(set) var firstInsert: Date?
    public private(set) var onboardingPagesReached = 0
    public private(set) var days: [UXDay] = []
    /// When the latest cancelled or failed dictation ended, until a start or a success settles it.
    private var lastUnsuccessful: Date?
    /// The day number that dictation ended on, so a retry is counted on that day and prunes with it.
    private var lastUnsuccessfulDay: Int?

    public init(installedOn: Date) { self.installedOn = installedOn }

    /// Counts `event` against the day `date` falls in, then drops days older than the kept window.
    public mutating func record(_ event: UXEvent, at date: Date, calendar: Calendar = .current) {
        let number = Self.dayNumber(date, calendar: calendar)
        if case .started = event, let ended = lastUnsuccessful, let endedDay = lastUnsuccessfulDay,
            date.timeIntervalSince(ended) <= Self.retryWindow,
            let index = days.firstIndex(where: { $0.number == endedDay })
        {
            days[index].retries += 1
        }
        var day = days.first { $0.number == number } ?? UXDay(number: number)
        switch event {
        case .started:
            day.started += 1
            if firstPress == nil { firstPress = date }
            clearUnsuccessful()
        case .ended(let outcome):
            day.outcomes[outcome, default: 0] += 1
            switch outcome {
            case .inserted:
                if firstInsert == nil { firstInsert = date }
                clearUnsuccessful()
            case .copied: clearUnsuccessful()
            case .cancelled, .failed:
                lastUnsuccessful = date
                lastUnsuccessfulDay = number
            }
        case .undone:
            day.undos += 1
        case .landed(let milliseconds):
            day.landings[UXLanding(milliseconds: milliseconds), default: 0] += 1
        case .onboardingPage(let page):
            onboardingPagesReached = max(onboardingPagesReached, page)
        }
        days.removeAll { $0.number == number }
        days.append(day)
        days.sort { $0.number < $1.number }
        prune(asOf: date, calendar: calendar)
    }

    /// Drops days older than the kept window as of `date`, so a ledger reopened after a long idle shows only live days.
    public mutating func prune(asOf date: Date, calendar: Calendar = .current) {
        let number = Self.dayNumber(date, calendar: calendar)
        days.removeAll { $0.number <= number - Self.daysKept }
    }

    private mutating func clearUnsuccessful() {
        lastUnsuccessful = nil
        lastUnsuccessfulDay = nil
    }

    /// The figures over the kept days. See `Docs/ux-measurement.md` for each definition.
    public var figures: UXFigures {
        let started = days.reduce(0) { $0 + $1.started }
        let retries = days.reduce(0) { $0 + $1.retries }
        let unsuccessful = days.reduce(0) {
            $0 + ($1.outcomes[.cancelled] ?? 0) + ($1.outcomes[.failed] ?? 0)
        }
        var landings: [UXLanding: Int] = [:]
        for day in days { landings.merge(day.landings, uniquingKeysWith: +) }
        return UXFigures(
            timeToFirstText: firstPress.flatMap { press in firstInsert.map { $0.timeIntervalSince(press) } },
            abandonment: started == 0 ? nil : Double(max(0, unsuccessful - retries)) / Double(started),
            started: started, undos: days.reduce(0) { $0 + $1.undos }, landings: landings)
    }

    private static func dayNumber(_ date: Date, calendar: Calendar) -> Int {
        let origin = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: date)).day ?? 0
    }
}

/// What the ledger says over its kept days.
public struct UXFigures: Sendable, Equatable {
    /// First press to first confirmed insert, in seconds; nil until both have happened.
    public let timeToFirstText: TimeInterval?
    /// Dictations cancelled or failed with no retry inside the window, over those started; nil with none started.
    public let abandonment: Double?
    public let started: Int
    public let undos: Int
    public let landings: [UXLanding: Int]
}

/// Where the ledger is kept on this Mac, owner-only; nothing here touches the network.
public struct UXLedgerStore: Sendable {
    private let url: URL

    public init(url: URL) { self.url = url }

    /// The saved ledger with days past the kept window dropped as of `date`, or nil when none is saved or it cannot be read.
    public func load(asOf date: Date = Date(), calendar: Calendar = .current) -> UXLedger? {
        guard
            var ledger = (try? Data(contentsOf: url)).flatMap({
                try? JSONDecoder().decode(UXLedger.self, from: $0)
            })
        else { return nil }
        ledger.prune(asOf: date, calendar: calendar)
        return ledger
    }

    public func save(_ ledger: UXLedger) throws {
        try PrivateFile.write(JSONEncoder().encode(ledger), to: url)
    }

    /// Removes the saved ledger, as Reset does.
    public func reset() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
