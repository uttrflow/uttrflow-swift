// The byte-bounded cache of thumbnails beside image clips.

import AppKit
import Foundation
import Observation
import UttrflowClipboard

/// Where a picture clip's thumbnail comes from; injected so the cache is testable without photographs.
struct PanelThumbnailSource: Sendable {
    /// The file and the longest edge to draw it at, in pixels; safe off the main actor.
    var load: @Sendable (URL, Int) -> NSImage?
}

/// Thumbnails beside image clips, decoded once off the main thread and bounded in measured bytes. See Docs/clipboard-budget.md.
@MainActor
@Observable
final class PanelThumbnails {
    static let shared = PanelThumbnails()

    /// The longest edge, in pixels: 34 points at the densest display Uttrflow runs on.
    static let maxPixel = 68

    /// The memory these may occupy, taken from the one place every such number lives.
    static let defaultBudget = ClipboardBudget.standard.images.bytes

    private let source: PanelThumbnailSource
    /// The most memory the decoded thumbnails may occupy, in bytes.
    private let budget: Int
    /// The decoded (or absent) thumbnail for a file that has been asked for; absent entries means a decode is in flight.
    private(set) var known: [URL: NSImage?] = [:]
    /// What each answer is costing, so the total is kept without measuring the whole cache.
    @ObservationIgnored private var cost: [URL: Int] = [:]
    @ObservationIgnored private var held = 0
    /// Least recently asked for, first; a plain array, because the cache is small.
    @ObservationIgnored private var order: [URL] = []
    /// Decodes in flight; one per file, so a row drawn twice does not decode twice.
    @ObservationIgnored private var inflight: [URL: Task<Void, Never>] = [:]
    /// When each failed decode was recorded, so a file restored later is decoded again.
    @ObservationIgnored private var missedAt: [URL: ContinuousClock.Instant] = [:]
    /// How long a failed decode is trusted before the file is read again.
    private let retryAfter: Duration

    init(
        source: PanelThumbnailSource = .system, budget: Int = PanelThumbnails.defaultBudget,
        retryAfter: Duration = .seconds(2)
    ) {
        self.source = source
        self.budget = max(budget, 0)
        self.retryAfter = retryAfter
    }

    /// What a decoded thumbnail costs, measured from the bitmap rather than the point size.
    static func bytes(of image: NSImage?) -> Int {
        guard let image else { return 0 }
        return image.representations.reduce(0) { total, representation in
            if let bitmap = representation as? NSBitmapImageRep {
                return total + bitmap.bytesPerRow * bitmap.pixelsHigh
            }
            if let cgImage = representation.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return total + cgImage.bytesPerRow * cgImage.height
            }
            return total
        }
    }

    /// The cached thumbnail for `file`, or `nil` while a miss is being decoded off the main actor.
    func thumbnail(for file: URL) -> NSImage? {
        forgetStaleMiss(file)
        if let remembered = known[file] {
            touch(file)
            return remembered
        }
        prepare(file)
        return nil
    }

    /// Starts an off-main decode for `file`; a no-op if one is already in flight, or the answer is already cached.
    func prepare(_ file: URL) {
        forgetStaleMiss(file)
        if known[file] != nil { return }
        if inflight[file] != nil { return }
        let source = self.source
        let maxPixel = Self.maxPixel
        inflight[file] = Task.detached(priority: .userInitiated) { [weak self] in
            let image = source.load(file, maxPixel)
            await self?.record(file, bytes: Loaded(image: image))
        }
    }

    /// Awaits the decode that `prepare(_:)` started for `file`; used by tests, not by the panel.
    func waitForIdle(file: URL) async {
        await inflight[file]?.value
    }

    /// Stored on `known` once the decode completes, even if the file is gone so the answer can be remembered.
    @MainActor
    private func record(_ file: URL, bytes: Loaded) {
        inflight[file] = nil
        let result = bytes.image
        let cost = Self.bytes(of: result)
        known[file] = result
        missedAt[file] = result == nil ? .now : nil
        self.cost[file] = cost
        held += cost
        touch(file)
        forgetTheLeastRecent()
    }

    /// Drops a remembered failure once it is older than `retryAfter`, so the next ask decodes again.
    private func forgetStaleMiss(_ file: URL) {
        guard let missed = missedAt[file], missed.duration(to: .now) >= retryAfter else { return }
        missedAt[file] = nil
        known.removeValue(forKey: file)
        cost.removeValue(forKey: file)
        order.removeAll { $0 == file }
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
            missedAt.removeValue(forKey: oldest)
        }
    }

    /// What the cache is holding, in bytes. Read by the tests that prove the bound.
    var bytesHeld: Int { held }
}

/// A wrapper that carries an `NSImage` between actors without `Sendable` conformance.
struct Loaded: @unchecked Sendable {
    let image: NSImage?
}
