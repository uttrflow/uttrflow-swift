public import Foundation
public import struct Foundation.Date
public import struct Foundation.UUID

/// A phrase the user says, and the block of text Uttrflow puts in its place.
///
/// The trigger is stored exactly as the user typed it into the editor, not in whatever
/// shape the matcher wants. Two reasons: the list on screen has to show them their own
/// words back, and the shape the matcher wants is a detail that has already changed
/// once — deriving it on demand from ``triggerWords`` means changing it again costs
/// nothing and cannot leave a stale copy on disk.
///
/// The counters are here rather than in a separate ledger because they are what the
/// list is sorted and judged by, and a snippet whose usage lives somewhere else is a
/// snippet whose usage can go missing when it is deleted.
public struct Snippet: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// What the user says. Free text, because they say words and not `;addr`.
    public let trigger: String
    /// What is put in its place, verbatim. Line breaks included: a standup update is
    /// three lines and flattening it would be Uttrflow editing the user's own writing.
    public let expansion: String
    public let created: Date
    /// How many dictations this snippet has fired in.
    public var timesUsed: Int
    /// When it last fired, or `nil` if it never has.
    ///
    /// Separate from ``created`` because the list shows both, and because "added last
    /// year, used this morning" and "added this morning, never used" are the two facts
    /// that tell the user whether a snippet is earning its row.
    public var lastUsed: Date?

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

    /// The same snippet, one use later.
    ///
    /// Returns a new value rather than mutating in place so the store can rebuild its
    /// list without holding a mutable copy of anything the caller still owns.
    ///
    /// - Parameter when: The instant the snippet fired.
    /// - Returns: A copy with the counter advanced and the clock set.
    public func used(at when: Date) -> Snippet {
        Snippet(
            id: id, trigger: trigger, expansion: expansion, created: created,
            timesUsed: timesUsed + 1, lastUsed: when)
    }

    /// The trigger as the matcher sees it: lower-cased runs of letters and digits.
    ///
    /// Everything the user typed that is not a letter or a digit is dropped, because
    /// none of it survives the round trip through speech anyway. Somebody who types
    /// "my address:" and then says "my address" has to be matched, or the trigger they
    /// can see in the list is not the trigger the product has.
    public var triggerWords: [String] { trigger.snippetWordRuns().map { $0.text.lowercased() } }

    /// Whether this snippet could ever fire.
    ///
    /// A trigger with no words in it would match at every position, and an expansion
    /// with nothing in it would replace words with silence. Both are things the editor
    /// can be asked to save, so both are checked here — once — rather than guessed at
    /// by each of the store and the matcher.
    public var isUsable: Bool {
        // Checked directly rather than through the tidier, which lives a layer up: the
        // question is only whether there is anything here at all, and Core must not
        // reach into UttrflowAI to ask it.
        !triggerWords.isEmpty
            && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
