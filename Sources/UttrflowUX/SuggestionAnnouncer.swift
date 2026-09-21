import UttrflowPredict

/// Decides what VoiceOver is told about the suggestion surface: each offer once when it appears, never again on a redraw.
public struct SuggestionAnnouncer: Sendable, Equatable {
    /// What makes one offer different from another, which a keystroke that only shortens the ghost leaves unchanged.
    private struct Offer: Sendable, Equatable {
        let candidates: [String]
        let selected: String?
        let acceptKey: AcceptKey
    }

    /// The offer last read aloud, or nothing once the surface has gone.
    private var spoken: Offer?

    public init() {}

    /// The text to announce for what is now on screen, or nothing when it was already announced or offers no text.
    public mutating func announcement(for presentation: SuggestionPresentation) -> String? {
        let label = presentation.accessibilityLabel
        guard presentation.style == .ghost, !label.isEmpty else {
            spoken = nil
            return nil
        }
        let offer = Offer(
            candidates: presentation.rows.map(\.candidate),
            selected: presentation.inline?.candidate, acceptKey: presentation.acceptKey)
        guard offer != spoken else { return nil }
        spoken = offer
        return label
    }

    /// Forgets the last offer, so the next one is announced even if it is the same text.
    public mutating func surfaceWithdrawn() {
        spoken = nil
    }
}
