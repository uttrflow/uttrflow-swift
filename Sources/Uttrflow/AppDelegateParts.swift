import Foundation

struct DismissalCountdown {
    private(set) var remaining: Duration
    private var startedAt: ContinuousClock.Instant?

    init(_ duration: Duration, at instant: ContinuousClock.Instant) {
        remaining = duration
        startedAt = instant
    }

    mutating func pause(at instant: ContinuousClock.Instant) {
        guard let startedAt else { return }
        remaining = max(.zero, remaining - startedAt.duration(to: instant))
        self.startedAt = nil
    }

    mutating func resume(at instant: ContinuousClock.Instant) {
        guard startedAt == nil, remaining > .zero else { return }
        startedAt = instant
    }

    func hasExpired(at instant: ContinuousClock.Instant) -> Bool {
        guard let startedAt else { return false }
        return startedAt.duration(to: instant) >= remaining
    }
}

/// Gives one retry exclusive ownership of the history badge until it finishes.
@MainActor
final class RetryBadgeOwnership {
    private(set) var recording: UUID?

    /// Refuses to transfer an in-flight retry's badge to a later click.
    func begin(_ id: UUID) -> Bool {
        guard recording == nil else { return false }
        recording = id
        return true
    }

    /// Finishes only the retry that currently owns the badge.
    @discardableResult
    func finish(_ id: UUID) -> Bool {
        guard recording == id else { return false }
        recording = nil
        return true
    }

    func clear() { recording = nil }
}
