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

    public func markers() -> PasteboardMarkers {
        PasteboardMarkers(types: NSPasteboard.general.types?.map(\.rawValue) ?? [])
    }

    /// The formatted flavour, HTML only; RTF would need a conversion on a tick that must stay cheap.
    public func html() -> String? {
        NSPasteboard.general.string(forType: .html)
    }

    /// The picture on the clipboard as PNG, its own bytes when it is PNG already; never via an uncompressed TIFF.
    public func image() -> (data: Data, width: Int, height: Int)? {
        let board = NSPasteboard.general
        if let png = board.data(forType: .png), let picture = PictureFlavour.fromPNG(png) {
            return picture
        }
        // Encoded pictures are converted once; `NSImage` is left for the flavours ImageIO cannot read.
        for type in [NSPasteboard.PasteboardType.tiff, .init("public.heic"), .init("public.jpeg")] {
            if let data = board.data(forType: type), let picture = PictureFlavour.converting(data) {
                return picture
            }
        }
        guard
            let item = board.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
            let image = item.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return PictureFlavour.png(of: image)
    }

    /// Read when the copy is noticed, since macOS does not say who wrote; the front app still served it.
    public func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
