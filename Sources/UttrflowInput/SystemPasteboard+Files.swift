// Puts copied files back on the system clipboard as the files themselves.

import AppKit
public import Foundation

extension SystemPasteboard {
    /// The files, in order, kept off Universal Clipboard because a path means nothing on another Mac.
    public func setFiles(_ urls: [URL]) -> PasteboardWriteResult {
        Self.writeFiles(urls, to: .general)
    }

    /// Writes the files and accepts the write only when the pasteboard reads the same files back.
    static func writeFiles(_ urls: [URL], to pasteboard: NSPasteboard) -> PasteboardWriteResult {
        guard !urls.isEmpty else { return .refused }
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard pasteboard.writeObjects(urls.map { $0 as NSURL }) else { return .refused }
        let back =
            pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard back?.map(\.standardizedFileURL) == urls.map(\.standardizedFileURL) else { return .refused }
        return .written(changeCount: pasteboard.changeCount)
    }
}
