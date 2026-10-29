public import struct Foundation.Data
public import UttrflowCore

/// Pastes an image from the clipboard panel without sending it into Uttrflow itself.
public struct PasteboardImageInsertionEngine: Sendable {
    private let focus: any AccessibilityFocus
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSender
    private let restoreDelay: Duration
    private let sleep: @Sendable (Duration) async -> Void

    /// How long the picture stays on the clipboard after ⌘V before the user's own contents return.
    public static let defaultRestoreDelay: Duration = .milliseconds(1500)

    public init(
        focus: any AccessibilityFocus, pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSender,
        restoreDelay: Duration = defaultRestoreDelay,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.focus = focus
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.restoreDelay = restoreDelay
        self.sleep = sleep
    }

    /// Writes the image, posts ⌘V while its target stays in front, and returns the delayed clipboard restore.
    @discardableResult
    public func insert(
        _ data: Data, targeting destination: InsertionDestination? = nil
    ) throws(TextInsertionError) -> Task<Void, Never>? {
        try PasteboardInsertionCancellation.requireLive(on: pasteboard)
        try PasteboardPasteAction.requireExternal(focus: focus)
        // Checked before the write too, so a switch already made never costs the user their clipboard.
        try TextInsertion.requireTarget(destination, focus: focus)
        let before = pasteboard.snapshot()
        let write = pasteboard.setImage(data)
        try PasteboardInsertionCancellation.requireLive(
            on: pasteboard, afterWritingAt: write.changeCount)
        guard write.didWrite else { throw .clipboardUnavailable }
        if let writeChangeCount = write.changeCount,
            let currentChangeCount = pasteboard.changeCount(),
            writeChangeCount != currentChangeCount
        {
            throw .clipboardChanged
        }
        try PasteboardPasteAction.postIfExternal(
            focus: focus, keystrokes: keystrokes, targeting: destination,
            pasteboard: pasteboard, writeChangeCount: write.changeCount)
        guard let before, let ours = write.changeCount else { return nil }
        let (pasteboard, delay, sleep) = (pasteboard, restoreDelay, sleep)
        return Task.detached {
            await sleep(delay)
            _ = pasteboard.restore(before, ifUnchangedSince: ours)
        }
    }
}
