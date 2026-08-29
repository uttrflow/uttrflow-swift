/// Reports what the user is working in, so the transformer can disambiguate terms.
///
/// Implementations must never block the recording path: when macOS withholds a piece
/// of context, the corresponding field is `nil` and the pipeline carries on.
public protocol ContextEngine: Sendable {
    func currentContext() async -> AppContext
}
