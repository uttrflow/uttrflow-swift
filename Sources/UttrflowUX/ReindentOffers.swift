// Asks whether each code clip can be re-indented once per text for the life of the app.
private import Synchronization
import UttrflowClipboard

/// Remembers whether a clip can be re-indented, so neither drawing the list nor opening the panel re-indents every clip.
final class ReindentOffers: Sendable, Equatable {
    /// The one memo every panel open shares, so an answer outlives the snapshot that asked; a test binds its own.
    @TaskLocal static var shared = ReindentOffers()

    /// A compact identity for the last text asked about, without keeping that text alive.
    private struct TextFingerprint: Equatable {
        let utf8Count: Int
        let hash: Int

        init(_ text: String) {
            utf8Count = text.utf8.count
            hash = text.hashValue
        }
    }

    /// Holds a compact identity for the last text asked about for a clip, and the answer.
    private struct Answer {
        let fingerprint: TextFingerprint
        let offers: Bool
    }

    private let answers = Mutex<[Clip.ID: Answer]>([:])
    /// How many clips are remembered before the memo starts over, so deleted clips cannot pile up.
    let limit: Int

    init(limit: Int = 10_000) {
        self.limit = limit
    }

    /// How many clips have an answer remembered.
    var count: Int { answers.withLock { $0.count } }

    /// Whether this clip still has an answer in the memo.
    func remembers(_ id: Clip.ID) -> Bool { answers.withLock { $0[id] != nil } }

    /// Drops answers for clips the current clipboard snapshot no longer contains.
    func prune(to liveIDs: Set<Clip.ID>) {
        answers.withLock { answers in
            answers = answers.filter { liveIDs.contains($0.key) }
        }
    }

    /// Answers whether the clip's text can be re-indented, asking only when this text has not been asked before.
    func offers(_ clip: Clip) -> Bool {
        guard clip.kind == .code else { return false }
        let fingerprint = TextFingerprint(clip.text)
        if let known = answers.withLock({ $0[clip.id] }), known.fingerprint == fingerprint {
            return known.offers
        }
        let offers = CodeReindent.reindented(clip.text) != nil
        answers.withLock { answers in
            if answers[clip.id] == nil, answers.count >= limit { answers.removeAll() }
            answers[clip.id] = Answer(fingerprint: fingerprint, offers: offers)
        }
        return offers
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: ReindentOffers, rhs: ReindentOffers) -> Bool { true }
}
