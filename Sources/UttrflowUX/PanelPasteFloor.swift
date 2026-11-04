import UttrflowCore

/// What keeps the words reachable when a text route gave up. See `Docs/app-quick-panel.md`.
public enum PanelPasteFloor {
    /// False only when the clipboard is someone else's newer copy, or the person cancelled.
    public static func keepsOnClipboard(after failure: any Error) -> Bool {
        switch failure as? TextInsertionError {
        case .clipboardChanged, .insertionCancelled: false
        default: true
        }
    }

    /// The report for a refused route, which claims a copy only when one was made.
    public static func result(copied: Bool) -> PanelPasteResult {
        copied ? .textRefused : .textCouldNotPaste
    }
}
