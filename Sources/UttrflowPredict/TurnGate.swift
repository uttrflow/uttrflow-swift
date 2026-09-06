public import struct Foundation.Date

/// Lets one turn run at a time, and lets a turn that never comes back be left behind rather than end the loop.
public struct TurnGate: Sendable, Equatable {
    /// How long a turn may run before the loop stops waiting for it; a read into another application can hang far longer.
    public static let stallSeconds: Double = 10

    /// What a request to run a turn comes to.
    public enum Admission: Sendable, Equatable {
        /// Nothing was running, so this turn runs under the given number.
        case free(Int)
        /// A turn is running and is still within its time, so this one waits its turn.
        case busy
        /// A turn ran past its time and is left behind; this one runs under the given number in its place.
        case stalled(Int)
    }

    /// The turn running, absent when none is.
    private var current: Int?
    /// When that turn was admitted, which is what a stall is measured from.
    private var startedAt: Date?
    /// How many turns have been admitted, which is where the next number comes from.
    private var issued = 0

    /// A gate with nothing running.
    public init() {}

    /// Whether a turn is running as far as the gate knows, which a stalled turn still counts as until replaced.
    public var isRunning: Bool { current != nil }

    /// Whether this turn is still the one running, which a turn left behind must ask before touching anything.
    public func isCurrent(_ turn: Int) -> Bool { current == turn }

    /// Admits a turn now, or says why not.
    public mutating func begin(at now: Date) -> Admission {
        if let startedAt {
            guard now.timeIntervalSince(startedAt) >= Self.stallSeconds else { return .busy }
            return .stalled(admit(at: now))
        }
        return .free(admit(at: now))
    }

    /// Ends a turn, true only for the one running, so a turn left behind ends without disturbing its replacement.
    public mutating func end(_ turn: Int) -> Bool {
        guard current == turn else { return false }
        current = nil
        startedAt = nil
        return true
    }

    /// Admits a turn under the next number and starts its clock.
    private mutating func admit(at now: Date) -> Int {
        issued += 1
        current = issued
        startedAt = now
        return issued
    }
}
