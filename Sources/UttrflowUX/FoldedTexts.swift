// Folds each clip's text for search once per text for as long as the panel is open.
private import Synchronization
import UttrflowClipboard

/// Remembers each clip's search-folded text, so a keystroke does not rebuild every clip's text.
final class FoldedTexts: Sendable, Equatable {
    /// Holds the source text and its bounded, folded search form.
    private struct Entry {
        let text: String
        let searchable: String
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
            return known.searchable
        }
        let searchableText = String(SearchFolding.boundedPrefix(of: clip.text))
        let searchable = fold(searchableText) ?? searchableText
        entries.withLock { $0[clip.id] = Entry(text: clip.text, searchable: searchable) }
        return searchable
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: FoldedTexts, rhs: FoldedTexts) -> Bool { true }
}
