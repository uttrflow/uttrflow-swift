import Foundation

/// An ISO-8601 timestamp, as the backend writes one.
///
/// Every date in the profile document except the entitlement's expiry is a string like
/// `2026-08-27T09:20:41.000Z`, and the expiry is a number because it is signed and its
/// shape is dictated by Swift's synthesised `Codable`. One `JSONDecoder` cannot be told
/// two date strategies, so the strings are converted here, field by field, and the number
/// is left to the strategy it already has.
///
/// Not a wrapper type around `Date`: a property wrapper or a `Codable` box would put a
/// second type in every signature that carries a date, for a conversion that belongs to
/// the wire and not to the model.
enum Timestamp {
    /// Parses what the backend sends, and what it might send.
    ///
    /// `toISOString()` in JavaScript always writes three fractional digits, so the first
    /// attempt is the one that will succeed. The second exists because "always" is a
    /// property of one implementation of one backend, and a date that arrives without
    /// milliseconds is not a reason to sign somebody out.
    static func date(from text: String) -> Date? {
        if let parsed = try? withMilliseconds.parse(text) { return parsed }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    static func string(from date: Date) -> String {
        withMilliseconds.format(date)
    }

    private static let withMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>, forKey key: Key
    ) throws -> Date {
        try parse(try container.decode(String.self, forKey: key), forKey: key, in: container)
    }

    static func decodeIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>, forKey key: Key
    ) throws -> Date? {
        guard let text = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return try parse(text, forKey: key, in: container)
    }

    /// The date `text` names, or the decoding error that says which key held the bad one.
    private static func parse<Key: CodingKey>(
        _ text: String, forKey key: Key, in container: KeyedDecodingContainer<Key>
    ) throws -> Date {
        guard let parsed = date(from: text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container, debugDescription: "not an ISO-8601 timestamp: \(text)")
        }
        return parsed
    }
}
