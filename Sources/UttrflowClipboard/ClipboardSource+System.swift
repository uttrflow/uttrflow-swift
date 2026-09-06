// The real clipboard.

public import struct Foundation.Data
import AppKit

/// The real clipboard, excluded from coverage; when to read it is decided and tested elsewhere.
public struct SystemClipboardSource: ClipboardSource {
    public init() {}

    public func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    public func text() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// The formatted flavour, HTML only; RTF would need a conversion on a tick that must stay cheap.
    public func html() -> String? {
        NSPasteboard.general.string(forType: .html)
    }

    /// The picture on the clipboard, normalised to PNG once, sized from the bitmap in pixels, not points.
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

    /// Read when the copy is noticed, since macOS does not say who wrote; the front app still served it.
    public func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
