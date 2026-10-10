// When a model gives its memory back under pressure, and when it may take it again.

import Dispatch

/// How pressed macOS says memory is.
enum MemoryPressureLevel: Sendable, Equatable {
    case normal
    case warning
    case critical

    /// The level a pressure event reports, taking the worst when it carries more than one.
    init(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            self = .critical
        } else if event.contains(.warning) {
            self = .warning
        } else {
            self = .normal
        }
    }
}

/// Decides how long a model released for memory waits before it loads or is released again. See `Docs/performance.md`.
struct ModelMemoryPressure: Sendable, Equatable {
    /// The calm the first reload waits for.
    let firstWait: Duration
    /// The longest wait, which is also how long a reload must hold before the wait starts over.
    let longestWait: Duration
    /// Whether the model is released for memory and not yet asked for again.
    private(set) var isReleased = false
    /// Whether pressure interrupted the first download, which must use the fetch-capable preparation path.
    private(set) var shouldResumeFirstDownload = false
    /// How long memory must stay calm before the next reload.
    private(set) var wait: Duration
    /// When the model was last asked for again after a release.
    private var reloadedAt: ContinuousClock.Instant?

    init(firstWait: Duration = .seconds(120), longestWait: Duration = .seconds(1_800)) {
        self.firstWait = firstWait
        self.longestWait = longestWait
        wait = firstWait
    }

    /// Records a release at this moment, doubling the wait when the last reload did not hold.
    mutating func released(at now: ContinuousClock.Instant) {
        if let reloadedAt {
            wait = reloadedAt.duration(to: now) < longestWait ? min(wait * 2, longestWait) : firstWait
        }
        isReleased = true
    }

    /// Records pressure that interrupted a first-run download.
    mutating func firstDownloadReleased(at now: ContinuousClock.Instant) {
        shouldResumeFirstDownload = true
        released(at: now)
    }

    /// Whether the last reload has held for the current wait, so a warning-level release now would not thrash.
    func allowsRelease(at now: ContinuousClock.Instant) -> Bool {
        guard let reloadedAt else { return true }
        return reloadedAt.duration(to: now) >= wait
    }

    /// Records that the model was asked for again at this moment.
    mutating func reloaded(at now: ContinuousClock.Instant) {
        isReleased = false
        shouldResumeFirstDownload = false
        reloadedAt = now
    }

    /// Forgets a release, since turning the feature off leaves nothing to reload.
    mutating func forget() {
        isReleased = false
        shouldResumeFirstDownload = false
    }
}
