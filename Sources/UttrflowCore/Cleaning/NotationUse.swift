/// That notation ran on a dictation and how many conversions it made, holding no word. See Docs/core-history-decoding.md.
public struct NotationUse: Sendable, Equatable, Codable {
    /// The destination kind for the notation.
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

    /// Reads a stored value, refusing a count not above zero so a damaged file claims nothing.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let conversions = try values.decode(Int.self, forKey: .conversions)
        guard conversions > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .conversions, in: values, debugDescription: "A notation holds a conversion.")
        }
        destination = try values.decode(Destination.self, forKey: .destination)
        self.conversions = conversions
    }

    private enum CodingKeys: String, CodingKey { case destination, conversions }
}
