// Folds each clip's text for search once per text for the life of the app.
import UttrflowClipboard

/// Remembers each clip's search-folded text, so a keystroke does not rebuild every clip's text.
final class FoldedTexts: Sendable {
    private let entries = Memo<Clip.ID, String, String>()
    private let fold: @Sendable (String) -> String?

    /// Builds an empty memo; `fold` is a seam so a test can count the folds.
    init(fold: @escaping @Sendable (String) -> String? = { SearchFolding.folded($0) }) {
        self.fold = fold
    }

    /// The clip's text as search compares it, folding only a text not folded before.
    func text(of clip: Clip) -> String {
        entries.value(for: clip.id, source: clip.text) {
            let searchableText = String(SearchFolding.boundedPrefix(of: clip.text))
            return fold(searchableText) ?? searchableText
        }
    }

    /// Drops folded text for clips outside the live clip list, so deleted clips cannot pile up.
    func prune(to liveIDs: Set<Clip.ID>) {
        entries.prune(to: liveIDs)
    }
}
