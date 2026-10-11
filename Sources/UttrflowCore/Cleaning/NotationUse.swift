/// That notation ran on a dictation and how many conversions it made, holding no word. See Docs/core-history-decoding.md.
public struct NotationUse: Sendable, Equatable, Codable {
    /// The kind of place the notation was written for.
    public let destination: Destination
    /// How many written places the notation pass changed; always above zero.
    public let conversions: Int

    private init(destination: Destination, conversions: Int) {
        self.destination = destination
        self.conversions = conversions
    }

    /// The notation a ledger shows for `destination`, or `nil` when the pass changed nothing or no ledger was kept.
    public static func reading(_ ledger: [ChangeLedgerEntry]?, in destination: Destination) -> NotationUse? {
        let made = ledger?.count { $0.pass == .codeEditorCommands } ?? 0
        return made > 0 ? NotationUse(destination: destination, conversions: made) : nil
    }

    /// Builds a stored value; `nil` for a count that is not above zero, so a damaged file claims nothing.
    public init?(storing destination: Destination, conversions: Int) {
        guard conversions > 0 else { return nil }
        self.init(destination: destination, conversions: conversions)
    }
}
