import AppKit
import Foundation
import UttrflowClipboard

/// Where a picture clip's thumbnail comes from.
///
/// Injected so the remembering can be tested without a disk full of photographs.
struct PanelThumbnailSource {
    /// The file, and the longest edge the panel will draw it at, in pixels.
    ///
    /// Main-actor, like the cache that calls it: decoding happens while the panel is
    /// being drawn, and a thumbnail that arrived on another thread would have to be
    /// handed back to this one anyway.
    var load: @MainActor (URL, Int) -> NSImage?
}

/// The little pictures beside image clips, decoded once.
///
/// The panel drew them with `NSImage(contentsOf:)` inside the row's body, which reads and
/// decodes the whole file — a screenshot is several megabytes — every time SwiftUI
/// evaluates that row. A lazy list re-evaluates rows as they come and go, so scrolling
/// past a handful of pictures meant decoding several megabytes per frame, which is
/// exactly what it felt like.
///
/// Held across openings, because the panel is opened hundreds of times a day and the same
/// recent clips are in it each time — but not for ever, and not by counting.
///
/// This is where the pictures actually cost memory. Their files never enter the process
/// at full size, so a clipboard of a thousand screenshots is a gigabyte on disk and
/// nothing at all in RAM until somebody scrolls past them — at which point it is this
/// cache, and only this cache, that decides how much of them the app is carrying. That is
/// why ``ClipboardBudget``'s picture quota is spent here rather than in the store.
///
/// Bounded in bytes rather than in entries. The bound used to be "two hundred, which is
/// about four megabytes", and the arithmetic behind that was a per-thumbnail estimate: a
/// 68-point square is *about* 18 KB. An estimate multiplied by a count is a budget that is
/// right until a Retina display, a wider row or a different bitmap format makes each one
/// twice the size, and then it is silently twice the budget with nothing to notice. Each
/// thumbnail is measured as it arrives and the total is what is capped, so the number in
/// the budget means what it says whatever the pictures turn out to weigh.
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
    /// What each answer is costing, so the total can be kept without measuring the whole
    /// cache on every insertion.
    private var cost: [URL: Int] = [:]
    private var held = 0
    /// Least recently asked for, first. A plain array because the cache is small enough
    /// that the bookkeeping a linked list would save is not worth the code to maintain.
    private var order: [URL] = []

    init(source: PanelThumbnailSource = .system, budget: Int = PanelThumbnails.defaultBudget) {
        self.source = source
        self.budget = max(budget, 0)
    }

    /// What a decoded thumbnail is costing, in bytes.
    ///
    /// Measured from the bitmap rather than from the `NSImage`'s point size, which is a
    /// drawing instruction and says nothing about what is being held. A representation
    /// that cannot say costs nothing here — an image with no bitmap is a placeholder or a
    /// failure, and both are already bounded by the entry itself.
    static func bytes(of image: NSImage?) -> Int {
        guard let image else { return 0 }
        return image.representations.reduce(0) { total, representation in
            guard let bitmap = representation as? NSBitmapImageRep else { return total }
            return total + bitmap.bytesPerRow * bitmap.pixelsHigh
        }
    }

    /// The thumbnail for a file, or `nil` when there is no longer a file to read — which
    /// the panel already has a sentence for, and which is remembered too so a missing
    /// picture is not looked for on every frame.
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

    /// Moves a file to the end of the queue: it has just been asked for, so it is the
    /// last thing that should be forgotten.
    private func touch(_ file: URL) {
        if let index = order.firstIndex(of: file) { order.remove(at: index) }
        order.append(file)
    }

    /// Drops the least recently asked-for thumbnails until the cache fits its budget.
    ///
    /// The most recent answer is kept even when it alone exceeds the budget, because the
    /// alternative is a cache that discards the very thing it was just asked for and
    /// decodes it again on the next frame — a budget of zero should mean "remember
    /// nothing between rows", not "thrash".
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
