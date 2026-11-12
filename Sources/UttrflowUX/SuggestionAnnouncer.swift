import UttrflowPredict

/// Decides what VoiceOver is told about the suggestion surface: each offer, and the dot Escape leaves, once when it appears, never again on a redraw.
public struct SuggestionAnnouncer: Sendable, Equatable {
    /// The quiet period that coalesces per-keystroke offer updates.
    public static let coalescingInterval: Duration = .milliseconds(150)
    /// What makes one offer different from another, including how much of the typing taking the leader would replace.
    private struct Offer: Sendable, Equatable {
        let candidates: [String]
        let selected: String?
        let acceptKey: AcceptKey
        let replaced: Int
        let notice: String?
    }

    /// The offer last read aloud, or nothing once the surface has gone.
    private var spoken: Offer?

    public init() {}

    /// The text to announce for what is now on screen, or nothing when it was already announced or offers no text.
    public mutating func announcement(for presentation: SuggestionPresentation) -> String? {
        let label = [presentation.announcementLabel, presentation.notice ?? ""].filter { !$0.isEmpty }
            .joined(separator: " ")
        guard presentation.style != .hidden, !presentation.announcementLabel.isEmpty else {
            spoken = nil
            return nil
        }
        let offer = Offer(
            candidates: presentation.rows.map(\.candidate),
            selected: presentation.inline?.candidate, acceptKey: presentation.acceptKey,
            replaced: presentation.inline?.edit.replacedCount ?? 0, notice: presentation.notice)
        guard offer != spoken else { return nil }
        spoken = offer
        return label
    }

    /// Forgets the last offer, so the next one is announced even if it is the same text.
    public mutating func surfaceWithdrawn() {
        spoken = nil
    }
}

/// Holds the latest changed offer until it is stable.
public struct SuggestionAnnouncementCoalescer: Sendable, Equatable {
    private var pending: String?
    private var lastUpdate: Duration?

    public init() {}

    /// Records a newly generated announcement and returns it when the offer stays unchanged for the quiet period.
    public mutating func offer(_ announcement: String?, at now: Duration) -> String? {
        guard let announcement else { return nil }
        pending = announcement
        lastUpdate = now
        return flushIfReady(at: now)
    }

    /// Returns the pending announcement after its quiet interval.
    public mutating func flushIfReady(at now: Duration) -> String? {
        guard let pending, let lastUpdate,
            now - lastUpdate >= SuggestionAnnouncer.coalescingInterval
        else { return nil }
        self.pending = nil
        self.lastUpdate = nil
        return pending
    }

    /// The remaining quiet interval, or nothing when no announcement is pending.
    public func remainingQuietInterval(at now: Duration) -> Duration? {
        guard let lastUpdate else { return nil }
        return max(.zero, SuggestionAnnouncer.coalescingInterval - (now - lastUpdate))
    }

    /// Drops queued text when the visible suggestion surface is withdrawn.
    public mutating func reset() {
        pending = nil
        lastUpdate = nil
    }
}
