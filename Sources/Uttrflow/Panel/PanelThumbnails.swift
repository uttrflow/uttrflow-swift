// The byte-bounded cache of thumbnails beside image clips.

import AppKit
import Foundation
import Observation
import SwiftUI
import UttrflowClipboard

/// Where a picture clip's thumbnail comes from; injected so the cache is testable without photographs.
struct PanelThumbnailSource: Sendable {
    /// The file and the longest edge to draw it at, in pixels; safe off the main actor.
    var load: @Sendable (URL, Int) -> NSImage?
}

/// Thumbnails beside image clips, decoded once off the main thread and bounded in measured bytes. See Docs/clipboard-budget.md.
@MainActor
final class PanelThumbnails {
    static let shared = PanelThumbnails()

    /// The longest edge, in pixels: 34 points at the densest display Uttrflow runs on.
    static let maxPixel = 68

    /// The memory these may occupy, taken from the one place every such number lives.
    static let defaultBudget = ClipboardBudget.standard.images.bytes

    /// Two ImageIO decodes keep browsing responsive without saturating every performance core.
    static let maximumConcurrentDecodes = 2

    private let source: PanelThumbnailSource
    /// The most memory the decoded thumbnails may occupy, in bytes.
    private let budget: Int
    /// The decoded (or absent) thumbnail for a file that has been asked for; absent entries means a decode is in flight.
    private(set) var known: [URL: NSImage?] = [:]
    @ObservationIgnored private var cost: [URL: Int] = [:]
    @ObservationIgnored private var held = 0
    @ObservationIgnored private var lruNodes: [URL: LRUNode] = [:]
    @ObservationIgnored private var oldest: LRUNode?
    @ObservationIgnored private var newest: LRUNode?
    @ObservationIgnored private var inflight: [URL: Task<Void, Never>] = [:]
    @ObservationIgnored private var queued: [URL: (selected: Bool, order: Int)] = [:]
    @ObservationIgnored private var abandoned: Set<URL> = []
    @ObservationIgnored private var queueOrder = 0
    @ObservationIgnored private var missedAt: [URL: ContinuousClock.Instant] = [:]
    @ObservationIgnored private let retryAfter: Duration
    @ObservationIgnored private let retryWait: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant

    init(
        source: PanelThumbnailSource = .system, budget: Int = PanelThumbnails.defaultBudget,
        retryAfter: Duration = .seconds(2),
        retryWait: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) {
        self.source = source
        self.budget = max(budget, 0)
        self.retryAfter = retryAfter
        self.retryWait = retryWait
        self.now = now
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

    /// The cached thumbnail for `file`, or `nil` when no image is cached.
    func thumbnail(for file: URL) -> NSImage? {
        known[file] ?? nil
    }

    /// Requests an off-main decode for a visible row; selected rows are scheduled first.
    func prepare(_ file: URL, selected: Bool = false) {
        forgetStaleMiss(file)
        if known[file] != nil { touch(file); return }
        abandoned.remove(file)
        if let queuedRequest = queued[file] {
            queued[file] = (selected: selected, order: queuedRequest.order)
            startQueuedDecodes()
            return
        }
        if inflight[file] != nil { return }
        queueOrder += 1
        queued[file] = (selected: selected, order: queueOrder)
        startQueuedDecodes()
    }

    /// Releases a row's demand, removing queued work or dropping an already-running result.
    func cancel(_ file: URL) {
        queued.removeValue(forKey: file)
        if let task = inflight[file] {
            abandoned.insert(file)
            task.cancel()
        }
        startQueuedDecodes()
    }

    /// Releases cached decodes while the system is under memory pressure.
    func releaseForMemoryPressure() {
        known.removeAll()
        cost.removeAll()
        held = 0
        lruNodes.removeAll()
        oldest = nil
        newest = nil
        missedAt.removeAll()
    }

    private func startQueuedDecodes() {
        while inflight.count < Self.maximumConcurrentDecodes,
            let next = queued.max(by: { lhs, rhs in
                if lhs.value.selected != rhs.value.selected { return !lhs.value.selected }
                return lhs.value.order > rhs.value.order
            })?.key
        {
            queued.removeValue(forKey: next)
            let source = self.source
            let maxPixel = Self.maxPixel
            let task = Task.detached(priority: .utility) { [weak self] in
                let loaded = await Self.decoding { Loaded(image: source.load(next, maxPixel)) }
                await self?.record(next, bytes: loaded)
            }
            inflight[next] = task
        }
    }

    /// Runs a decode on a serial queue of its own, which gets a thread on busy cores, never on the cooperative pool it would block.
    private nonisolated static func decoding(_ decode: @escaping @Sendable () -> Loaded) async -> Loaded {
        await withCheckedContinuation { continuation in
            DispatchQueue(label: "com.uttrflow.panel-thumbnail-decode", qos: .utility).async {
                continuation.resume(returning: decode())
            }
        }
    }

    /// What is already decoded for `file`, touching nothing, so a view can start from it without a flash.
    func cached(_ file: URL) -> NSImage? {
        known[file] ?? nil
    }

    /// The thumbnail for `file`, awaiting an off-main decode when it is not yet known.
    func picture(for file: URL) async -> NSImage? {
        if let remembered = cached(file) { return remembered }
        prepare(file)
        await waitForIdle(file: file)
        return cached(file)
    }

    /// Awaits the decode that `prepare(_:)` started for `file`.
    func waitForIdle(file: URL) async {
        while queued[file] != nil || inflight[file] != nil {
            if let task = inflight[file] {
                await task.value
                if inflight[file] != nil { await Task.yield() }
            } else {
                await Task.yield()
            }
        }
    }

    /// Waits before a visible row asks `prepare(_:)` to retry a remembered miss.
    func waitBeforeRetry() async throws {
        try await retryWait(retryAfter)
    }

    /// Stored on `known` once the decode completes, even if the file is gone so the answer can be remembered.
    @MainActor
    private func record(_ file: URL, bytes: Loaded) {
        inflight[file] = nil
        if abandoned.remove(file) != nil {
            startQueuedDecodes()
            return
        }
        let result = bytes.image
        let cost = Self.bytes(of: result)
        known[file] = result
        missedAt[file] = result == nil ? now() : nil
        self.cost[file] = cost
        held += cost
        touch(file)
        forgetTheLeastRecent()
        startQueuedDecodes()
    }

    /// Drops a remembered failure once it is older than `retryAfter`, so the next ask decodes again.
    private func forgetStaleMiss(_ file: URL) {
        guard let missed = missedAt[file], missed.duration(to: now()) >= retryAfter else { return }
        missedAt[file] = nil
        known.removeValue(forKey: file)
        cost.removeValue(forKey: file)
        removeFromLRU(file)
    }

    /// Moves a file to the end of the queue, so it is the last thing forgotten.
    private func touch(_ file: URL) {
        if let node = lruNodes[file] {
            unlink(node)
            append(node)
        } else {
            append(LRUNode(file))
        }
    }

    /// Drops the least recently used thumbnails until the cache fits; the newest stays even over budget.
    private func forgetTheLeastRecent() {
        while held > budget, lruNodes.count > 1, let node = oldest {
            let file = node.file
            removeFromLRU(file)
            held -= cost.removeValue(forKey: file) ?? 0
            known.removeValue(forKey: file)
            missedAt.removeValue(forKey: file)
        }
    }

    private func append(_ node: LRUNode) {
        node.previous = newest
        node.next = nil
        newest?.next = node
        newest = node
        oldest = oldest ?? node
        lruNodes[node.file] = node
    }

    private func unlink(_ node: LRUNode) {
        node.previous?.next = node.next
        node.next?.previous = node.previous
        if oldest === node { oldest = node.next }
        if newest === node { newest = node.previous }
        node.previous = nil
        node.next = nil
    }

    private func removeFromLRU(_ file: URL) {
        guard let node = lruNodes.removeValue(forKey: file) else { return }
        unlink(node)
    }

    /// What the cache is holding, in bytes. Read by the tests that prove the bound.
    var bytesHeld: Int { held }
}

private final class LRUNode {
    let file: URL
    var previous: LRUNode?
    var next: LRUNode?
    init(_ file: URL) { self.file = file }
}

/// A wrapper that carries an `NSImage` between actors without `Sendable` conformance.
struct Loaded: @unchecked Sendable {
    let image: NSImage?
}

/// One picture clip's thumbnail, which alone redraws when its decode lands.
struct PanelThumbnailView: View {
    let file: URL
    let isSelected: Bool
    private let thumbnails: PanelThumbnails
    @State private var picture: NSImage?

    /// Starts from what the cache already holds, so a row scrolled back into view draws at once.
    init(file: URL, isSelected: Bool = false, thumbnails: PanelThumbnails = .shared) {
        self.file = file
        self.isSelected = isSelected
        self.thumbnails = thumbnails
        _picture = State(initialValue: thumbnails.cached(file))
    }

    var body: some View {
        Group {
            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.panelCard
            }
        }
        // Decoded off the main actor; a row reused for a different file starts over.
        .task(id: file) {
            while !Task.isCancelled {
                picture = thumbnails.cached(file)
                thumbnails.prepare(file, selected: isSelected)
                await thumbnails.waitForIdle(file: file)
                guard !Task.isCancelled else { return }
                picture = thumbnails.cached(file)
                guard picture == nil else { return }
                do {
                    try await thumbnails.waitBeforeRetry()
                } catch {
                    return
                }
            }
        }
        .onChange(of: isSelected) { _, selected in
            thumbnails.prepare(file, selected: selected)
        }
        .onDisappear {
            thumbnails.cancel(file)
        }
    }
}
