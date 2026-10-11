public import Foundation
public import UttrflowCore

/// Pastes copied files from the clipboard panel without sending them into Uttrflow itself.
public struct PasteboardFileInsertionEngine: Sendable {
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

    /// Puts the files on the clipboard without pasting; the pasteboard is untouched when it refuses.
    public func copy(_ urls: [URL]) throws(TextInsertionError) {
        guard pasteboard.setFiles(urls).didWrite else { throw .clipboardUnavailable }
    }

    /// Writes the files and posts ⌘V only while the external application they are meant for stays in front.
    public func insert(
        _ urls: [URL], targeting destination: InsertionDestination? = nil
    ) throws(TextInsertionError) {
        try PasteboardInsertionCancellation.requireLive(on: pasteboard)
        try PasteboardPasteAction.requireExternal(focus: focus)
        // Checked before the write too, so a switch already made never costs the user their clipboard.
        try TextInsertion.requireTarget(destination, focus: focus)
        let write = pasteboard.setFiles(urls)
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
    }
}
