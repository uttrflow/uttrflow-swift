// What left this Mac and why, counted by purpose for 30 days and kept on this Mac only.

public import struct Foundation.Date
public import struct Foundation.URL
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder
public import class Foundation.FileManager
public import struct Foundation.Data

import struct Synchronization.Mutex

/// Every reason this app opens a connection; dictation is not one of them. See `Docs/offline.md`.
public enum NetworkPurpose: String, CaseIterable, Codable, Sendable {
    /// Signing in and reading the account's profile.
    case account
    /// Fetching a speech or suggestion model.
    case modelDownload
    /// Asking the update feed whether a newer build exists.
    case updateCheck
    /// Sending a crash or hang report, only while that switch is on.
    case crashReport
    /// Sending usage statistics, only while that switch is on.
    case usageStatistics
}

/// How many requests one purpose made, and when the last one was.
public struct NetworkTally: Codable, Equatable, Sendable {
    /// Requests inside the window.
    public var count: Int
    /// The most recent of them.
    public var last: Date

    /// A tally of `count` requests, the latest at `last`.
    public init(count: Int, last: Date) {
        self.count = count
        self.last = last
    }
}

/// Requests per purpose per day, numbers and dates only, for the last ``window`` days.
public struct NetworkActivity: Codable, Equatable, Sendable {
    /// How many days the record covers.
    public static let windowDays = 30

    /// One day's requests for one purpose.
    struct Day: Codable, Equatable, Sendable {
        let purpose: NetworkPurpose
        let day: Date
        var count: Int
        var last: Date
    }

    /// Every day with a request, oldest first.
    private(set) var days: [Day]

    /// Nothing recorded.
    public static let none = NetworkActivity(days: [])

    /// Adds one request for `purpose` at `moment`, forgetting whatever has fallen out of the window.
    public mutating func record(_ purpose: NetworkPurpose, at moment: Date) {
        prune(at: moment)
        let day = Self.startOfDay(moment)
        if let index = days.firstIndex(where: { $0.purpose == purpose && $0.day == day }) {
            days[index].count += 1
            days[index].last = max(days[index].last, moment)
        } else {
            days.append(Day(purpose: purpose, day: day, count: 1, last: moment))
        }
    }

    /// Drops every day older than the window ending at `moment`.
    public mutating func prune(at moment: Date) {
        let span = Double(Self.windowDays - 1) * Self.secondsPerDay
        let cutoff = Self.startOfDay(moment).addingTimeInterval(-span)
        days.removeAll { $0.day < cutoff }
    }

    /// The tally for each purpose inside the window ending at `moment`; a purpose with none is absent.
    public func tallies(at moment: Date) -> [NetworkPurpose: NetworkTally] {
        var pruned = self
        pruned.prune(at: moment)
        return pruned.days.reduce(into: [:]) { tallies, day in
            let previous = tallies[day.purpose]
            tallies[day.purpose] = NetworkTally(
                count: (previous?.count ?? 0) + day.count,
                last: max(previous?.last ?? day.last, day.last))
        }
    }

    private static let secondsPerDay: Double = 86_400

    /// Days are counted in UTC so a change of time zone cannot split or merge one.
    private static func startOfDay(_ moment: Date) -> Date {
        let seconds = moment.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / secondsPerDay).rounded(.down) * secondsPerDay)
    }
}

/// The one record every connection is written to, saved beside this build's other local stores.
public final class NetworkActivityLedger: Sendable {
    /// The ledger the app writes to, in this build's Application Support folder.
    public static let shared = NetworkActivityLedger(
        file: LocalStoreEntry.networkActivity.location(in: .applicationSupportDirectory))

    private let file: URL?
    private let state: Mutex<NetworkActivity?>

    /// Saves to `file`, or keeps the record in memory alone when it is `nil`.
    public init(file: URL?) {
        self.file = file
        self.state = Mutex(file == nil ? NetworkActivity.none : nil)
    }

    /// Counts one request for `purpose`; a write that fails loses the count, never the request.
    public func record(_ purpose: NetworkPurpose, at moment: Date = Date()) {
        let snapshot = state.withLock { state -> NetworkActivity in
            var activity = state ?? load()
            activity.record(purpose, at: moment)
            state = activity
            return activity
        }
        save(snapshot)
    }

    /// What is recorded now, read from disk the first time.
    public func activity() -> NetworkActivity {
        state.withLock { state in
            let activity = state ?? load()
            state = activity
            return activity
        }
    }

    private func load() -> NetworkActivity {
        // A path, not a URL read, so nothing here could ever fetch from the network.
        guard let file, let data = FileManager.default.contents(atPath: file.path(percentEncoded: false)),
            let activity = try? JSONDecoder().decode(NetworkActivity.self, from: data)
        else { return .none }
        return activity
    }

    private func save(_ activity: NetworkActivity) {
        guard let file, let data = try? JSONEncoder().encode(activity) else { return }
        try? PrivateFile.write(data, to: file)
    }
}
