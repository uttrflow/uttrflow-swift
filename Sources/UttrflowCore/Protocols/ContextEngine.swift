/// Reports what the user is working in without ever blocking the recording path; withheld context is `nil`.
public protocol ContextEngine: Sendable {
    /// What the user is looking at right now.
    func currentContext() async -> AppContext
    /// A count that rises with every key, click or application switch, or `nil` from an engine that does not watch them.
    func inputsSeen() async -> Int?
}

extension ContextEngine {
    /// An engine that does not watch input cannot vouch that the screen is unchanged, so every read is taken.
    public func inputsSeen() async -> Int? { nil }
}
