// Puts copied files back on the system clipboard as the files themselves.

import AppKit
public import Foundation

extension SystemPasteboard {
    /// The files, in order, kept off Universal Clipboard because a path means nothing on another Mac.
    public func setFiles(_ urls: [URL]) -> PasteboardWriteResult {
        Self.writeFiles(urls, to: .general)
    }

}
