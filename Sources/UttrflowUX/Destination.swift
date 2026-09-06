// The one vocabulary for places in the app: a destination, and the tabs it can name.

/// Somewhere in the app the user can be sent, named the same way by every surface that sends them.
public enum Destination: Sendable, Equatable, Hashable {
    case onboarding
    case settings(SettingsTab)
    case main(MainTab)
}

/// The tabs of the settings window, in the approved design's order rather than alphabetically.
public enum SettingsTab: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case general
    case languages
    case dictation
    case suggestions
    case privacy
}

/// The sidebar's pages, in the approved design's order; Settings is absent because it is a window.
public enum MainTab: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Where the window opens, and the only page about the person rather than about a feature.
    case home
    case dictation
    case history
    case dictionary
    case corrections
    case insights
    case snippets
    case style
    case diagnostics
    case account
}
