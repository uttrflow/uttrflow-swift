// The read-only clipboard the watcher polls.

public import struct Foundation.Data

/// The machine's clipboard, read-only; not `UttrflowInput`'s `Pasteboard`, which this module must not link.
public protocol ClipboardSource: Sendable {
    /// The number macOS increments on every write to the clipboard, the only change signal it offers.
    func changeCount() -> Int

    /// The current contents as text, or `nil` when the clipboard holds something else.
    func text() -> String?
    /// The formatted flavour, read alongside the plain one, never instead of it.
    func html() -> String?

    /// The picture on the clipboard as PNG bytes and pixel size, read only when there is no text.
    func image() -> (data: Data, width: Int, height: Int)?

    /// The application in front of the user, shown as provenance and never a basis for a decision.
    func frontmostApplicationName() -> String?
}
