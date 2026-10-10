// The menu bar's copy of the last few dictations.

import Foundation
import UttrflowHistory
import UttrflowUX

/// One finished dictation, the record `DictationHistoryStore` keeps; the menu ignores what it lacks room for.
typealias RecentDictation = DictationRecord

/// A recent dictation as a menu can afford to show it.
struct RecentDictationPreview: Sendable, Equatable, Identifiable {
    /// The shortened, single-line form. A menu item must not be a paragraph wide.
    let title: String
    /// Whether the complete text must also stay out of the menu tooltip.
    let isSecret: Bool
    /// The whole thing, because inserting or copying a shortened version would be a lie.
    let dictation: RecentDictation

    var id: UUID { dictation.id }
}

/// The last few dictations, newest first: the menu bar's main-actor view of the store's history.
struct RecentDictations: Sendable, Equatable {
    /// Five, matching the Recent section of the menu.
    static let defaultCapacity = 5

    let capacity: Int
    private(set) var entries: [RecentDictation] = []

    /// Keeps the first `capacity` of `records`, newest first; the rest belong to the history page.
    init(capacity: Int = RecentDictations.defaultCapacity, showing records: [RecentDictation] = []) {
        // Clamped: a negative capacity would trap in `prefix`.
        self.capacity = max(0, capacity)
        entries = Array(records.prefix(self.capacity))
    }

    /// Shows a dictation at the head of the menu at once; the store's next `init` replaces the lot.
    mutating func add(_ dictation: RecentDictation) {
        entries.insert(dictation, at: 0)
        entries = Array(entries.prefix(capacity))
    }

    /// Empties the menu's copy. Clearing what is *kept* is the store's job.
    mutating func clear() {
        entries.removeAll()
    }

    var previews: [RecentDictationPreview] { previews(secretPhrases: []) }

    /// The rows, masking a dictation that holds the text of a snippet marked secret.
    func previews(secretPhrases: [String] = []) -> [RecentDictationPreview] {
        entries.map { dictation in
            let presentation = DictationTextPresentation(dictation.text, secretPhrases: secretPhrases)
            return RecentDictationPreview(
                title: presentation.isSecret ? presentation.displayText : Self.shortened(dictation.text),
                isSecret: presentation.isSecret,
                dictation: dictation)
        }
    }

    /// Collapses a dictation onto one short line, whitespace first.
    static func shortened(_ text: String, limit: Int = 48) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }

        var head = String(collapsed.prefix(limit))
        // Collapsing leaves at most one space at the cut, and "late …" reads as a typo.
        if head.hasSuffix(" ") { head.removeLast() }
        return head + "…"
    }
}
