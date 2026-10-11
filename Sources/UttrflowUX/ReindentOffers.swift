// Asks whether each code clip can be re-indented once per text for the life of the app.
import UttrflowClipboard

/// Remembers whether a clip can be re-indented, so neither drawing the list nor opening the panel re-indents every clip.
final class ReindentOffers: Sendable {
    /// A compact identity for the last text asked about, without keeping that text alive.
    private struct TextFingerprint: Equatable {
        let utf8Count: Int
        let hash: Int

        init(_ text: String) {
            utf8Count = text.utf8.count
            hash = text.hashValue
        }
    }

    private let answers: Memo<Clip.ID, TextFingerprint, Bool>
    /// How many clips are remembered before the memo starts over, so deleted clips cannot pile up.
    let limit: Int

    init(limit: Int = 10_000) {
        self.limit = limit
        answers = Memo(limit: limit)
    }

    /// How many clips have an answer remembered.
    var count: Int { answers.count }

    /// Whether this clip still has an answer in the memo.
    func remembers(_ id: Clip.ID) -> Bool { answers.remembers(id) }

    /// Drops answers for clips the current clipboard snapshot no longer contains.
    func prune(to liveIDs: Set<Clip.ID>) {
        answers.prune(to: liveIDs)
    }

    /// Answers whether the clip's text can be re-indented, asking only when this text has not been asked before.
    func offers(_ clip: Clip) -> Bool {
        guard clip.kind == .code else { return false }
        let fingerprint = TextFingerprint(clip.text)
        return answers.value(for: clip.id, source: fingerprint) {
            CodeReindent.reindented(clip.text) != nil
        }
    }

}
