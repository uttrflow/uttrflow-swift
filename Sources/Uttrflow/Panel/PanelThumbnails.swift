// The byte-bounded cache of thumbnails beside image clips.

import AppKit
import Foundation
import UttrflowClipboard

/// Where a picture clip's thumbnail comes from; injected so the cache is testable without photographs.
struct PanelThumbnailSource {
    /// The file and the longest edge to draw it at, in pixels; main-actor, like the cache that calls it.
    var load: @MainActor (URL, Int) -> NSImage?
}

/// Thumbnails beside image clips, decoded once and bounded in measured bytes. See Docs/clipboard-budget.md.
@MainActor
final class PanelThumbnails {
    static let shared = PanelThumbnails()

    /// The longest edge, in pixels: 34 points at the densest display Uttrflow runs on.
    static let maxPixel = 68

    /// The memory these may occupy, taken from the one place every such number lives.
    static let defaultBudget = ClipboardBudget.standard.images.bytes

    private let source: PanelThumbnailSource
    /// The most memory the decoded thumbnails may occupy, in bytes.
    private let budget: Int
    private var known: [URL: NSImage?] = [:]
    /// What each answer is costing, so the total is kept without measuring the whole cache.
    private var cost: [URL: Int] = [:]
    private var held = 0
    /// Least recently asked for, first; a plain array, because the cache is small.
    private var order: [URL] = []

    init(source: PanelThumbnailSource = .system, budget: Int = PanelThumbnails.defaultBudget) {
        self.source = source
        self.budget = max(budget, 0)
    }

    /// What a decoded thumbnail costs, measured from the bitmap rather than the point size.
    static func bytes(of image: NSImage?) -> Int {
        guard let image else { return 0 }
        return image.representations.reduce(0) { total, representation in
            guard let bitmap = representation as? NSBitmapImageRep else { return total }
            return total + bitmap.bytesPerRow * bitmap.pixelsHigh
        }
    }

    /// The thumbnail for a file, or `nil` for a file that has gone, remembered too so it is not re-read.
    func thumbnail(for file: URL) -> NSImage? {
        if let remembered = known[file] {
            touch(file)
            return remembered
        }
        let found = source.load(file, Self.maxPixel)
        let bytes = Self.bytes(of: found)
        known[file] = found
        cost[file] = bytes
        held += bytes
        touch(file)
        forgetTheLeastRecent()
        return found
    }

    /// Moves a file to the end of the queue, so it is the last thing forgotten.
    private func touch(_ file: URL) {
        if let index = order.firstIndex(of: file) { order.remove(at: index) }
        order.append(file)
    }

    /// Drops the least recently used thumbnails until the cache fits; the newest stays even over budget.
    private func forgetTheLeastRecent() {
        while held > budget, order.count > 1 {
            let oldest = order.removeFirst()
            held -= cost.removeValue(forKey: oldest) ?? 0
            known.removeValue(forKey: oldest)
        }
    }

    /// What the cache is holding, in bytes. Read by the tests that prove the bound.
    var bytesHeld: Int { held }
}
