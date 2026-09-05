/// Reports what the user is working in without ever blocking the recording path; withheld context is `nil`.
public protocol ContextEngine: Sendable {
    /// What the user is looking at right now.
    func currentContext() async -> AppContext
}
