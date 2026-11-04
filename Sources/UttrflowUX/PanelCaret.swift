public import UttrflowCore

/// Where a clip belongs once the panel has closed. See `Docs/app-quick-panel.md`.
public enum PanelCaret {
    /// The focus owner while the captured application is still in front, since another app's floating panel can hold the caret.
    public static func destination(
        captured: InsertionDestination, frontmost: InsertionDestination?,
        focused: InsertionDestination?, ownProcess: Int32
    ) -> InsertionDestination {
        guard let frontmost, captured.isSameApplication(as: frontmost), let focused,
            focused.processIdentifier != ownProcess
        else { return captured }
        return focused
    }
}
