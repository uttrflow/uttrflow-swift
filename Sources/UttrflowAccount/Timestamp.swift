import Foundation

/// An ISO-8601 timestamp as the backend writes one, converted per field since the signed expiry is a number.
enum Timestamp {
    /// Parses with three fractional digits first, as `toISOString()` writes them, and without them second.
    static func date(from text: String) -> Date? {
        if let parsed = try? withMilliseconds.parse(text) { return parsed }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    /// Formats with three fractional digits, as the backend writes.
    static func string(from date: Date) -> String {
        withMilliseconds.format(date)
    }

    /// The backend's spelling.
    private static let withMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Decodes the string under `key` as a date.
    static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>, forKey key: Key
    ) throws -> Date {
        try parse(try container.decode(String.self, forKey: key), forKey: key, in: container)
    }

    /// Decodes the string under `key` as a date, or `nil` when absent.
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
