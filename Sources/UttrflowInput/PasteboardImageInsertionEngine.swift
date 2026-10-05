public import struct Foundation.Data
public import UttrflowCore

/// Pastes an image from the clipboard panel without sending it into Uttrflow itself.
public struct PasteboardImageInsertionEngine: Sendable {
    private let focus: any AccessibilityFocus
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSender

    public init(
        focus: any AccessibilityFocus, pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSender
    ) {
        self.focus = focus
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    /// Writes the image and posts ⌘V only if an external application remains frontmost.
    public func insert(_ data: Data) throws(TextInsertionError) {
        try PasteboardInsertionCancellation.requireLive(on: pasteboard)
        try PasteboardPasteAction.requireExternal(focus: focus)
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
            focus: focus, keystrokes: keystrokes,
            pasteboard: pasteboard, writeChangeCount: write.changeCount)
    }
}
