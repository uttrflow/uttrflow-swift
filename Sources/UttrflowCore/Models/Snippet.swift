public import Foundation
public import struct Foundation.Date
public import struct Foundation.UUID

/// A phrase the user says and the text put in its place; the trigger is kept as typed, its match form derived.
public struct Snippet: Sendable, Equatable, Identifiable, Codable {
    /// Stable identity across edits.
    public let id: UUID
    /// What the user says, as free text, because they say words and not `;addr`.
    public let trigger: String
    /// What is put in its place, verbatim, line breaks included.
    public let expansion: String
    /// When the user added it.
    public let created: Date
    /// How many dictations this snippet has fired in.
    public var timesUsed: Int
    /// When it last fired, or `nil` if it never has; shown beside ``created`` so the list says which rows earn it.
    public var lastUsed: Date?

    /// A snippet with fresh counters unless told otherwise.
    public init(
        id: UUID = UUID(), trigger: String, expansion: String, created: Date,
        timesUsed: Int = 0, lastUsed: Date? = nil
    ) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.created = created
        self.timesUsed = timesUsed
        self.lastUsed = lastUsed
    }

    /// The same snippet one use later, as a new value so the store never holds a mutable copy.
    public func used(at when: Date) -> Snippet {
        Snippet(
            id: id, trigger: trigger, expansion: expansion, created: created,
            timesUsed: timesUsed + 1, lastUsed: when)
    }

    /// The trigger as the matcher sees it: lower-cased runs of letters and digits, all that survives speech.
    public var triggerWords: [String] { trigger.snippetWordRuns().map { $0.text.lowercased() } }

    /// Whether this snippet can ever fire: a wordless trigger matches everywhere, an empty expansion deletes.
    public var isUsable: Bool {
        // Checked directly, not through the tidier, because Core must not reach into UttrflowAI.
        !triggerWords.isEmpty
            && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
