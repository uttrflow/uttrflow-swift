import Foundation

/// A pasteboard that hands over and takes back its items as bytes, so capture and restore need no platform type.
protocol RawItemPasteboard: SnapshotRestorablePasteboard {
    /// Every item with each type's bytes; a type whose data cannot be read is left out.
    var rawItems: [[String: Data]] { get }

    /// Replaces the contents with these items, keeping them off Universal Clipboard.
    func replaceRawItems(_ items: [[String: Data]]) -> Bool
}

extension RawItemPasteboard {
    func snapshot() -> PasteboardSnapshot? { PasteboardSnapshot(items: rawItems) }

    func restore(_ snapshot: PasteboardSnapshot, ifUnchangedSince changeCount: Int) -> Bool {
        guard self.changeCount() == changeCount else { return false }
        guard !snapshot.items.isEmpty else { return discardContents(ifUnchangedSince: changeCount) }
        return replaceRawItems(snapshot.items)
    }
}
