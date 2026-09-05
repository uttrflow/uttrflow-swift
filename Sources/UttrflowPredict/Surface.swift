public import struct Foundation.Date

/// One text field, told apart from every other field the user types in.
public struct Surface: Hashable, Sendable {
    /// The application the field belongs to.
    public let bundleIdentifier: String
    /// The field's Accessibility role, which separates a search box from a document.
    public let role: String
    /// What tells this field from another of the same role, when it names itself.
    public let locator: String?
    /// The page host for a web field, or the working directory for a terminal.
    public let scope: String?

    public init(bundleIdentifier: String, role: String, locator: String? = nil, scope: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.locator = locator
        self.scope = scope
    }
}

/// One value the user finished entering, and what has happened to it since.
public struct Entry: Sendable, Equatable {
    /// The text as it was committed.
    public let text: String
    /// How many times it has been entered here.
    public let count: Int
    /// How many times it was offered and taken.
    public let accepted: Int
    /// How many times it was offered and typed past.
    public let rejected: Int
    /// How many of the entries came from accepting our own suggestion rather than typing.
    public let selfSourced: Int
    /// When it was last entered.
    public let lastUsed: Date

    public init(
        text: String, count: Int, accepted: Int = 0, rejected: Int = 0, selfSourced: Int = 0,
        lastUsed: Date
    ) {
        self.text = text
        self.count = count
        self.accepted = accepted
        self.rejected = rejected
        self.selfSourced = selfSourced
        self.lastUsed = lastUsed
    }
}
