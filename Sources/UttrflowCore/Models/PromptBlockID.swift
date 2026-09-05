/// Names the style rules and examples a formatter shows the model; a string, so a block is data rather than a case.
public struct PromptBlockID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, Codable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}
