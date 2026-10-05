/// What a destination does with the text after it lands, which sets how much a wrong word costs there. See `Docs/adapters.md` §7.
public enum Consequence: String, Sendable, Equatable, CaseIterable {
    /// The text sits in the field until the person acts on it.
    case stores
    /// A typed Return can send it to someone.
    case sends
    /// A typed Return can run it.
    case executes
    /// A typed Return can open or act on it, as an address or search field does.
    case navigates

    /// Whether Return finishes the text here rather than breaking a line in it.
    public var returnActs: Bool { self != .stores }
}
