public import struct Foundation.Data

/// The machine's clipboard, as everything above it needs to see it.
///
/// Read-only, and that is the whole point of the boundary. The watcher never writes —
/// the app does that when it pastes a clip — so a protocol that offered a write would
/// be offering the one operation nothing here should perform, and would tie this module
/// to the insertion engine that legitimately does.
///
/// `UttrflowInput` already has a `Pasteboard` protocol with a superset of these calls.
/// This is not that one, because `UttrflowClipboard` does not depend on `UttrflowInput`
/// and should not: the clipboard panel is opened by people who never dictate, and a
/// module that had to link the typing machinery to poll a change count would have the
/// dependency graph exactly backwards. `SystemPasteboard` satisfies this protocol
/// almost by accident, which is the cheap way to reconcile them later if it is ever
/// worth doing.
public protocol ClipboardSource: Sendable {
    /// A number the system increments whenever anything writes to the clipboard,
    /// including other applications. The only change signal macOS offers.
    func changeCount() -> Int

    /// The current contents as text, or `nil` when the clipboard holds something else —
    /// an image, a file promise, a PDF.
    func text() -> String?
    /// The formatted flavour, when the clipboard is carrying one.
    ///
    /// Read alongside the plain one rather than instead of it: a clip needs both, and a
    /// source that could only answer with the rich form would make every plain paste a
    /// conversion that might fail.
    func html() -> String?

    /// K4 — the picture on the clipboard, as PNG bytes and its size in pixels.
    ///
    /// Read only when there is no text, because most copies are text and decoding an
    /// image on every tick would spend the whole budget on the common case.
    func image() -> (data: Data, width: Int, height: Int)?

    /// The application in front of the user right now, which is as close as macOS lets
    /// anyone get to "who copied this". Shown as provenance and never used to decide
    /// anything, so being wrong about it costs a line of grey text.
    func frontmostApplicationName() -> String?
}
