import Foundation

/// When clipboard capture is paused until, and the timer that ends the pause.
@MainActor
final class ClipboardPause {
    /// How long a pause lasts.
    static let duration: TimeInterval = 60 * 60

    private(set) var until: Date?
    private var timer: Task<Void, Never>?
    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        until: Date? = nil,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.until = until
        self.now = now
        self.sleep = sleep
    }

    var isActive: Bool {
        guard let until else { return false }
        return until > now()
    }

    /// Starts a pause, or ends one, and drops any running timer.
    @discardableResult
    func set(_ isPaused: Bool) -> Date? {
        cancelTimer()
        until = isPaused ? now().addingTimeInterval(Self.duration) : nil
        return until
    }

    /// Adopts a stored deadline, for example after preferences are restored.
    func load(_ stored: Date?) {
        cancelTimer()
        until = stored
    }

    func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Runs `onExpiry` once the deadline passes, unless a timer already runs or nothing is paused.
    func startTimerIfNeeded(onExpiry: @escaping @MainActor () -> Void) {
        guard timer == nil, until != nil else { return }
        let sleep = self.sleep
        timer = Task { [weak self] in
            // Re-read the clock after each sleep: a backward clock step must not end the pause early.
            while let self, !Task.isCancelled, let deadline = self.until {
                let delay = deadline.timeIntervalSince(self.now())
                guard delay > 0 else { break }
                try? await sleep(.seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            self.until = nil
            self.timer = nil
            onExpiry()
        }
    }
}
