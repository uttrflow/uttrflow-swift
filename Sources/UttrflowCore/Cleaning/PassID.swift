/// Names one cleaning pass, so a word can say which pass removed or rewrote it.
public struct PassID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral,
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
