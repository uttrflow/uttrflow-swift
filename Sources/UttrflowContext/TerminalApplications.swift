/// The applications whose text areas hold commands rather than prose, until a dialect registry knows better.
public enum TerminalApplications {
    /// The terminals this recognises, which Accessibility cannot tell from a document by role alone.
    public static let bundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    /// Whether this application's text areas are shells, which are never written fluently enough to quiet.
    public static func contains(_ bundleIdentifier: String) -> Bool {
        bundleIdentifiers.contains(bundleIdentifier)
    }
}
