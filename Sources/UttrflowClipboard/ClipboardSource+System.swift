// The real clipboard.

public import struct Foundation.Data
public import struct Foundation.URL
public import struct UttrflowCore.PasteboardMarkers
import AppKit
private import os
private import Synchronization

/// The real clipboard, excluded from coverage; when to read it is decided and tested elsewhere.
public struct SystemClipboardSource: ClipboardProvenanceSource {
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "clipboard")

    /// Where the picture bounds come from; the watcher's own bound covers text.
    private let budget: ClipboardBudget

    public init(budget: ClipboardBudget = .standard) {
        self.budget = budget
    }

    /// One content read of the general pasteboard at a time in this process: two at once race on its type cache and crash.
    private static let contents = Mutex(())

    private static func reading<Value>(_ read: () -> Value) -> Value {
        contents.withLock { _ in read() }
    }

    public func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    public func text() -> String? {
        Self.reading { NSPasteboard.general.string(forType: .string) }
    }

    /// RTF bytes within the same single-clip bound used for plain text.
    public func rtf() -> Data? {
        guard
            let data = Self.reading({ NSPasteboard.general.data(forType: .rtf) }),
            budget.largestClip == 0 || data.count <= budget.largestClip
        else {
            return nil
        }
        return data
    }

    public func markers() -> PasteboardMarkers {
        PasteboardMarkers(types: Self.reading { NSPasteboard.general.types?.map(\.rawValue) } ?? [])
    }

    func clipboardProvenance() -> ClipboardProvenance {
        Self.reading {
            let pasteboard = NSPasteboard.general
            let types = pasteboard.types?.map(\.rawValue) ?? []
            return ClipboardProvenance(
                types: types,
                writerValue: types.contains(ClipboardProvenance.writerType)
                    ? pasteboard.string(forType: .init(ClipboardProvenance.writerType)) : nil)
        }
    }

    /// The local files on the clipboard, in the order the file manager wrote them.
    public func fileURLs() -> [URL] {
        Self.reading {
            let urls = NSPasteboard.general.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            return (urls as? [URL]) ?? []
        }
    }

    /// The formatted flavour, HTML only; RTF has its own bounded import.
    public func html() -> String? {
        Self.reading { NSPasteboard.general.string(forType: .html) }
    }

    /// The picture on the clipboard as PNG, judged by its header first and never via a TIFF macOS translates for us.
    public func image() -> (data: Data, width: Int, height: Int)? {
        Self.reading { Self.picture(on: .general, within: budget) }
    }

    public func hasPicture() -> Bool {
        guard let types = Self.reading({ NSPasteboard.general.types }) else { return false }
        return types.contains { Self.pictureFlavours.contains($0) }
    }

    /// The flavours asked for, compressed first: asking for TIFF makes macOS decode a JPEG or HEIC into one.
    static let pictureFlavours: [NSPasteboard.PasteboardType] = [
        .png, .init("public.heic"), .init("public.jpeg"), .tiff,
    ]

    /// The picture on `board`, the first flavour ImageIO reads, or `nil` when its header is over the bound.
    static func picture(
        on board: NSPasteboard, within budget: ClipboardBudget
    ) -> (data: Data, width: Int, height: Int)? {
        for type in pictureFlavours {
            guard let data = board.data(forType: type) else { continue }
            switch PictureFlavour.reading(data, within: budget) {
            case .kept(let picture): return picture
            case .refused(let width, let height):
                log.notice("a copied picture of \(width)×\(height) is over the bound; it is not kept")
                return nil
            case .unreadable: continue
            }
        }
        // `NSImage` is left for the flavours ImageIO cannot read, and sized before it is drawn.
        guard
            let item = board.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
            PictureFlavour.fits((Int(item.size.width), Int(item.size.height)), within: budget),
            let image = item.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return PictureFlavour.png(of: image)
    }

    /// Read when the copy is noticed, since macOS does not say who wrote; the front app still served it.
    public func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    public func frontmostApplicationBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func frontmostApplication() -> (name: String?, bundleIdentifier: String?) {
        let application = NSWorkspace.shared.frontmostApplication
        return (application?.localizedName, application?.bundleIdentifier)
    }
}
