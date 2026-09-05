/// A BCP-47 primary subtag in lowercase, so `"EN"`, `"en-US"` and `"en"` are one language everywhere.
public struct LanguageCode: Hashable, Sendable, CustomStringConvertible {
    /// The normalised primary subtag, e.g. `"en"`.
    public let value: String

    /// Keeps the primary subtag of any BCP-47 identifier, or `nil` when it has no alphabetic one.
    public init?(_ identifier: String) {
        let separators: Set<Character> = ["-", "_"]
        let primarySubtag =
            identifier
            .drop(while: \.isWhitespace)
            .prefix { !separators.contains($0) && !$0.isWhitespace }
            .lowercased()

        guard !primarySubtag.isEmpty,
            primarySubtag.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }

        self.value = primarySubtag
    }

    public var description: String { value }
}

/// The languages the product names by hand.
extension LanguageCode {
    /// `"en"`.
    public static let english = LanguageCode(unchecked: "en")
    /// `"hi"`.
    public static let hindi = LanguageCode(unchecked: "hi")

    /// Bypasses validation for compile-time-known-good literals.
    private init(unchecked value: String) {
        self.value = value
    }
}

/// Encoded as its bare string, and refused on decode when that string is not a language.
extension LanguageCode: Codable {
    /// Decodes a string, throwing `dataCorrupted` when it is not a BCP-47 identifier.
    public init(from decoder: any Decoder) throws {
        let identifier = try decoder.singleValueContainer().decode(String.self)
        guard let code = LanguageCode(identifier) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "'\(identifier)' is not a valid BCP-47 language identifier."
                )
            )
        }
        self = code
    }

    /// Encodes the bare subtag.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
