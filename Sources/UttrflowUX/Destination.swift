/// Somewhere in the app the user can be sent.
///
/// Four surfaces open windows — the menu bar, the floating button's recovery action,
/// onboarding when it finishes, and the main window's own navigation — and before this
/// existed each would have had to name its destination in its own way. One vocabulary
/// means a new place to go is added once, and every surface can already reach it.
public enum Destination: Sendable, Equatable, Hashable {
    case onboarding
    case settings(SettingsTab)
    case main(MainTab)
}

/// The tabs of the settings window, in the order they are shown.
///
/// `CaseIterable` is the point: the window builds its tab bar from this, so a tab
/// cannot be added to the enum and then forgotten in the view. The order is the
/// approved design's sidebar order (`Design/_gen_settings.py`), not alphabetical —
/// tidying it into alphabetical order would silently rearrange the window.
public enum SettingsTab: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case general
    case languages
    case dictation
    case privacy
}

/// The destinations in the sidebar, in the order they are shown.
///
/// The order is the approved design's (`Design/_gen_shell.py`) and is not alphabetical:
/// Dictation first because it is what the window is for, Account last because it is
/// visited once. Settings is deliberately absent — it opens its own window, and putting
/// it here would make it a page that behaves unlike every other page in the list.
public enum MainTab: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Where the window opens, and the only page that is about the person rather than
    /// about a feature. Everything on it also lives somewhere else; what it adds is a
    /// place to arrive.
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
