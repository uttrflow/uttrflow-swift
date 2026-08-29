/// A BCP-47 primary language subtag, normalised to lowercase (`"en"`, `"hi"`).
///
/// Speech engines, transformers and the UI all need to agree on how a language is
/// spelled. Normalising once, here, keeps `"EN"`, `"en-US"` and `"en"` from being
/// treated as three different languages further down the pipeline.
public struct LanguageCode: Hashable, Sendable, CustomStringConvertible {
    /// The normalised primary subtag, e.g. `"en"`.
    public let value: String

    /// Creates a language code from any BCP-47 identifier, keeping only the primary
    /// subtag. Returns `nil` when `identifier` contains no alphabetic primary subtag.
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

extension LanguageCode {
    public static let english = LanguageCode(unchecked: "en")
    public static let hindi = LanguageCode(unchecked: "hi")

    /// Bypasses validation for compile-time-known-good literals.
    private init(unchecked value: String) {
        self.value = value
    }
}

extension LanguageCode: Codable {
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

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
