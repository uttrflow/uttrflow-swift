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

    /// Runs `copy` when the clipboard may be taken, and says whether the words are now on it.
    @MainActor public static func keep(
        after failure: any Error, copy: @MainActor () async -> Bool
    ) async -> Bool {
        guard keepsOnClipboard(after: failure) else { return false }
        return await copy()
    }

    /// Keeps the words if it may, then reports what really happened.
    @MainActor public static func result(
        after failure: any Error, copy: @MainActor () async -> Bool
    ) async -> PanelPasteResult {
        result(copied: await keep(after: failure, copy: copy))
    }

    /// The report for a refused route, which claims a copy only when one was made.
    public static func result(copied: Bool) -> PanelPasteResult {
        copied ? .textRefused : .textCouldNotPaste
    }
}
