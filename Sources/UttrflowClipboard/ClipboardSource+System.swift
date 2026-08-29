public import struct Foundation.Data
import AppKit

/// The real clipboard.
///
/// Untestable by construction — it is the machine's own clipboard, shared with every
/// other application on it, and there is nothing to assert about these three lines that
/// is not simply "macOS did what we asked". Excluded from the coverage gate; everything
/// that decides *when* to read it, and what to make of what comes back, is decided in
/// ``PasteboardWatcher`` and ``ClipKindDetector`` and tested there against a substitute.
public struct SystemClipboardSource: ClipboardSource {
    public init() {}

    public func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    public func text() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// The formatted flavour, if the copier put one there.
    ///
    /// HTML only, deliberately. RTF is the other flavour applications write, and reading
    /// it would mean converting it — work on a tick that must stay cheap, and a conversion
    /// that can fail. A clip copied from somewhere that offers only RTF keeps its plain
    /// form and no formatting, which is an honest outcome rather than a guessed one.
    public func html() -> String? {
        NSPasteboard.general.string(forType: .html)
    }

    /// K4 — the picture on the clipboard, normalised to PNG.
    ///
    /// Normalised on the way in rather than at the moment of the paste: the clipboard
    /// carries TIFF as often as PNG, a screenshot is enormous in TIFF, and converting once
    /// when the copy happens beats converting on every draw of a thumbnail.
    ///
    /// Size is taken from the bitmap in pixels rather than from `NSImage.size`, which is
    /// in points — on this display those differ by a factor of two, and a row reporting
    /// half the real dimensions of a screenshot would simply be wrong.
    public func image() -> (data: Data, width: Int, height: Int)? {
        guard
            let item = NSPasteboard.general.readObjects(
                forClasses: [NSImage.self], options: nil)?.first as? NSImage,
            let tiff = item.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return (png, bitmap.pixelsWide, bitmap.pixelsHigh)
    }

    /// Read at the moment the copy is noticed rather than recorded by the copier,
    /// because macOS does not say who wrote to the clipboard. Within a fifth of a
    /// second of a ⌘C the front application is still the one that served it.
    public func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
