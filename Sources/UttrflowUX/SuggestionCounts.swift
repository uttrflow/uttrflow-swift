/// The counts held by the suggestion corpus.
public struct SuggestionCounts: Sendable, Equatable {
    public let entries: Int
    public let uses: Int
    public let accepted: Int
    public let rejected: Int
    public let selfSourced: Int

    /// Builds counts from the suggestion corpus.
    public init(entries: Int, uses: Int, accepted: Int, rejected: Int, selfSourced: Int) {
        self.entries = entries
        self.uses = uses
        self.accepted = accepted
        self.rejected = rejected
        self.selfSourced = selfSourced
    }
}
