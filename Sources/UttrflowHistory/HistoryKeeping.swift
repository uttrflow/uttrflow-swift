/// Which finished dictations may be written to history at all; the one place that is decided.
public struct HistoryKeeping: Sendable, Equatable {
    /// Whether no transcript is kept anywhere, whatever app it went into.
    public let keepsNothing: Bool

    /// Bundle identifiers, lower-cased, whose dictations are inserted and then forgotten.
    public let excludedApplications: Set<String>

    /// Keeps every dictation; what the app passes until the list is stored in settings.
    public static let everything = HistoryKeeping()

    /// Takes the global switch and the per-app list; identifiers compare without case.
    public init(keepsNothing: Bool = false, excludedApplications: Set<String> = []) {
        self.keepsNothing = keepsNothing
        self.excludedApplications = Set(excludedApplications.map { $0.lowercased() })
    }

    /// Whether a dictation into `applicationIdentifier` may be kept; an unknown app is listed in no list.
    public func keeps(applicationIdentifier: String?) -> Bool {
        guard !keepsNothing else { return false }
        guard let applicationIdentifier else { return true }
        return !excludedApplications.contains(applicationIdentifier.lowercased())
    }
}
