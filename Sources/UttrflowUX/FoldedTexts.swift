// Folds each clip's text for search once per text for as long as the panel is open.
private import Synchronization
import UttrflowClipboard

/// Remembers each clip's search-folded text, so a keystroke does not rebuild every clip's text.
final class FoldedTexts: Sendable, Equatable {
    /// Holds the last text folded for a clip, and its folding; `nil` when folding changes nothing.
    private struct Entry {
        let text: String
        let folded: String?
    }

    private let entries = Mutex<[Clip.ID: Entry]>([:])
    private let fold: @Sendable (String) -> String?

    /// Builds an empty memo; `fold` is a seam so a test can count the folds.
    init(fold: @escaping @Sendable (String) -> String? = { SearchFolding.folded($0) }) {
        self.fold = fold
    }

    /// The clip's text as search compares it, folding only a text not folded before.
    func text(of clip: Clip) -> String {
        if let known = entries.withLock({ $0[clip.id] }), known.text == clip.text {
            return known.folded ?? clip.text
        }
        let folded = fold(clip.text)
        entries.withLock { $0[clip.id] = Entry(text: clip.text, folded: folded) }
        return folded ?? clip.text
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: FoldedTexts, rhs: FoldedTexts) -> Bool { true }
}
