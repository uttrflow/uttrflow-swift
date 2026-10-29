import AppKit
import Foundation

/// Captures and rewrites a pasteboard's items, taking the pasteboard so a test can use a private one.
enum PasteboardContents {
    /// Every item with each type's bytes; a type whose data cannot be read is left out.
    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [String: Data]()) { entry, type in
                if let data = item.data(forType: type) { entry[type.rawValue] = data }
            }
        }
        return PasteboardSnapshot(items: items)
    }

    /// Replaces the contents with the snapshot's items, keeping them off Universal Clipboard.
    static func write(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) -> Bool {
        let items = snapshot.items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        return pasteboard.writeObjects(items)
    }
}

extension SystemPasteboard: SnapshotRestorablePasteboard {
    func snapshot() -> PasteboardSnapshot? { PasteboardContents.capture(from: .general) }

    func restore(_ snapshot: PasteboardSnapshot, ifUnchangedSince changeCount: Int) -> Bool {
        guard NSPasteboard.general.changeCount == changeCount else { return false }
        guard !snapshot.items.isEmpty else { return discardContents(ifUnchangedSince: changeCount) }
        return PasteboardContents.write(snapshot, to: .general)
    }
}
