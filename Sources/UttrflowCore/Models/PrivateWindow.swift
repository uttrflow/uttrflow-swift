// The one test of whether a window is a private-browsing window, read by every learner on this Mac.

/// Whether a window names itself private; its title is the only sign a browser publishes. See Docs/predict.md.
public enum PrivateWindow {
    /// The words a browser puts in the title of a private window; the probe table is in Docs/app-dictionary.md.
    static let titleMarkers = ["(Incognito)", "InPrivate", "Private Browsing"]

    /// Whether `title` carries a private-window marker, in any case; a window with no title is not private.
    public static func isNamed(by title: String?) -> Bool {
        guard let title else { return false }
        return titleMarkers.contains { title.localizedCaseInsensitiveContains($0) }
    }
}

extension AppContext {
    /// Whether the focused window names itself private, so dictation learns nothing from it.
    public var isInPrivateWindow: Bool { PrivateWindow.isNamed(by: documentName) }
}
