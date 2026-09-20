// Asks whether each code clip can be re-indented once per text for as long as the panel is open.
private import Synchronization
import UttrflowClipboard

/// Remembers whether a clip can be re-indented, so drawing the list does not re-indent every clip.
final class ReindentOffers: Sendable, Equatable {
    /// Holds the last text asked about for a clip, and the answer.
    private struct Answer {
        let text: String
        let offers: Bool
    }

    private let answers = Mutex<[Clip.ID: Answer]>([:])

    init() {}

    /// Answers whether the clip's text can be re-indented, asking only when this text has not been asked before.
    func offers(_ clip: Clip) -> Bool {
        guard clip.kind == .code else { return false }
        if let known = answers.withLock({ $0[clip.id] }), known.text == clip.text {
            return known.offers
        }
        let offers = CodeReindent.reindented(clip.text) != nil
        answers.withLock { $0[clip.id] = Answer(text: clip.text, offers: offers) }
        return offers
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: ReindentOffers, rhs: ReindentOffers) -> Bool { true }
}
