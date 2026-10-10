// Tests for the retention rules, which need no store and no files.

import Foundation
import Testing

@testable import UttrflowClipboard

/// What stays in a list of clips, checked without a store.
@Suite("Retention policy")
struct RetentionPolicyTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func clip(_ text: String, daysAgo: Double, pinned: Bool = false, order: UInt64? = nil) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: now.addingTimeInterval(-daysAgo * 86_400),
            lastUsedOrder: order, isPinned: pinned)
    }

    private var policy: RetentionPolicy { RetentionPolicy(budget: .standard) }

    /// An unkept clip older than the window goes; a pinned one of the same age stays.
    @Test("an old clip goes and a pinned one stays")
    func windowSparesKept() {
        let retention = ClipRetention(days: 7, now: now)
        let list = [
            clip("fresh", daysAgo: 1), clip("old", daysAgo: 30), clip("pinned", daysAgo: 30, pinned: true),
        ]
        #expect(policy.retained(list, keeping: retention).map(\.text) == ["fresh", "pinned"])
    }

    /// Zero days keeps no history, but still keeps what the user kept.
    @Test("zero days keeps only kept clips")
    func zeroDays() {
        let retention = ClipRetention(days: 0, now: now)
        let list = [clip("fresh", daysAgo: 0), clip("pinned", daysAgo: 0, pinned: true)]
        #expect(policy.retained(list, keeping: retention).map(\.text) == ["pinned"])
    }

    /// A pool over its record cap drops nothing kept and keeps the first clips of the list.
    @Test("a pool keeps only its item cap")
    func itemCap() {
        let tier = ClipboardTier(bytes: 1_000_000, items: 2)
        let budget = ClipboardBudget(
            ceiling: 10_000_000, copied: tier, dictation: tier, images: tier, largestClip: 1_000_000,
            largestPicture: 0, pictureEdge: 0, disk: 0)
        let retention = ClipRetention(days: 7, now: now)
        let list = (0..<4).map { clip("c\($0)", daysAgo: 0) }
        let kept = RetentionPolicy(budget: budget).retained(list, keeping: retention)
        #expect(kept.map(\.text) == ["c0", "c1"])
    }

    /// Over the memory quota the least recently used clip goes first.
    @Test("over its memory quota the least recently used clip goes")
    func memoryQuota() {
        let tier = ClipboardTier(bytes: 10, items: 100)
        let budget = ClipboardBudget(
            ceiling: 10_000_000, copied: tier, dictation: tier, images: tier, largestClip: 1_000_000,
            largestPicture: 0, pictureEdge: 0, disk: 0)
        let list = [clip("aaaaaa", daysAgo: 0, order: 9), clip("bbbbbb", daysAgo: 0, order: 1)]
        let kept = RetentionPolicy(budget: budget).retained(
            list, keeping: ClipRetention(days: 7, now: now))
        #expect(kept.map(\.text) == ["aaaaaa"])
    }

    /// Weight counts text and formatted text, never a picture's file.
    @Test("weight counts both flavours of text")
    func weighing() {
        let rich = Clip(text: "abc", kind: .text, copiedAt: now, richText: "<b>abc</b>")
        #expect(RetentionPolicy.weight(of: rich) == 3 + 10)
        #expect(RetentionPolicy.weight(of: [rich, rich]) == 26)
    }

    /// The largest-clip bound refuses a clip that is too heavy.
    @Test("a clip over the largest-clip bound does not fit")
    func largestClip() {
        let tier = ClipboardTier(bytes: 100, items: 10)
        let budget = ClipboardBudget(
            ceiling: 1_000, copied: tier, dictation: tier, images: tier, largestClip: 5,
            largestPicture: 0, pictureEdge: 0, disk: 0)
        let policy = RetentionPolicy(budget: budget)
        #expect(policy.fitsLargestClip(clip("12345", daysAgo: 0)))
        #expect(!policy.fitsLargestClip(clip("123456", daysAgo: 0)))
    }
}
