import Foundation
import UttrflowHistory

/// One finished dictation, under the name the menu code has always used for it.
///
/// The very same record ``DictationHistoryStore`` keeps, rather than a second struct
/// with the same fields — which is what this used to be, and one shape too many to
/// keep in step. The menu simply ignores the fields it has no room for.
typealias RecentDictation = DictationRecord

/// A recent dictation as a menu can afford to show it.
struct RecentDictationPreview: Sendable, Equatable, Identifiable {
    /// The shortened, single-line form. A menu item must not be a paragraph wide.
    let title: String
    /// The whole thing, because inserting or copying a shortened version would be a lie.
    let dictation: RecentDictation

    var id: UUID { dictation.id }
}

/// The last few dictations, newest first: the menu bar's view of the stored history.
///
/// A view, not a store. ``DictationHistoryStore`` holds every dictation and owns both
/// the retention promise and the order; this keeps the head of that list on the main
/// actor, where a menu is drawn synchronously the instant the user clicks and cannot
/// stop to await an actor. Nothing here re-decides what survives or how it is sorted —
/// there is one answer to each and it is the store's.
struct RecentDictations: Sendable, Equatable {
    /// Five, matching the Recent section of the menu: enough to reach for the thing you
    /// just said, short enough that the menu stays a menu.
    static let defaultCapacity = 5

    let capacity: Int
    private(set) var entries: [RecentDictation] = []

    /// - Parameters:
    ///   - capacity: How many the menu shows.
    ///   - records: What the store last handed over, newest first. Only the first
    ///     `capacity` of them are kept, because the rest belong to the history page.
    init(capacity: Int = RecentDictations.defaultCapacity, showing records: [RecentDictation] = []) {
        // Clamped rather than trusted: a negative capacity would trap in `prefix`, and a
        // menu with no Recent section is a far better outcome than a crash.
        self.capacity = max(0, capacity)
        entries = Array(records.prefix(self.capacity))
    }

    /// Shows a dictation at the head of the menu, dropping the oldest once full.
    ///
    /// The local echo of a write, not a second place the truth is kept: it exists so
    /// the menu is right the moment a dictation lands, rather than a round trip to the
    /// store's actor later. The next ``init(capacity:showing:)`` from the store
    /// replaces the lot, so a write that never reached the disk cannot linger here.
    mutating func add(_ dictation: RecentDictation) {
        entries.insert(dictation, at: 0)
        entries = Array(entries.prefix(capacity))
    }

    /// Empties the menu's copy. Clearing what is *kept* is the store's job.
    mutating func clear() {
        entries.removeAll()
    }

    var previews: [RecentDictationPreview] {
        entries.map { RecentDictationPreview(title: Self.shortened($0.text), dictation: $0) }
    }

    /// Collapses a dictation onto one short line.
    ///
    /// Whitespace goes first: speech arrives with line breaks and doubled spaces in it,
    /// and a menu item renders those as a ragged gap rather than as structure.
    static func shortened(_ text: String, limit: Int = 48) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }

        var head = String(collapsed.prefix(limit))
        // Collapsing leaves at most one space at the cut, and "late …" reads as a typo.
        if head.hasSuffix(" ") { head.removeLast() }
        return head + "…"
    }
}
