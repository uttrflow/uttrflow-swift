/// The name of one format adapter, as history, diagnostics and the override store record it. See `Docs/adapters.md` §1.
public struct AdapterID: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How the person wants one app's words formatted; `auto` lets the registry choose. See `Docs/adapters.md` §6.
public enum AdapterMode: Sendable, Equatable {
    /// The registry picks the adapter on the evidence, which is what every app starts with.
    case auto
    /// Never a notation adapter: the words are formatted as prose for the app's destination.
    case prose
    /// Always this adapter, whatever the evidence says.
    case forced(AdapterID)
}
