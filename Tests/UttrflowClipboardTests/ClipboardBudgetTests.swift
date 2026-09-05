// Tests for the clipboard's memory budget.

import Foundation
import Testing

@testable import UttrflowClipboard

/// The bounds on what the clipboard may cost; a guarantee rather than a saving. See Docs/clipboard-budget.md.
@Suite("What the clipboard may cost")
struct ClipboardBudgetTests {
    private func clip(
        _ text: String, origin: ClipOrigin = .copied, usedAt: TimeInterval = 0,
        pinned: Bool = false, alias: String? = nil
    ) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: noon.addingTimeInterval(usedAt), source: "Notes",
            origin: origin, lastUsedAt: noon.addingTimeInterval(usedAt), alias: alias,
            isPinned: pinned)
    }

    // MARK: - The shape of the budget itself

    /// The one arithmetic mistake this type makes impossible: raising a tier without lowering another.
    @Test("the tiers fit inside the ceiling")
    func tiersFitTheCeiling() {
        #expect(ClipboardBudget.standard.claimed <= ClipboardBudget.standard.ceiling)
    }

    /// The numbers may be edited per build; what must not be edited away is that they are all present.
    @Test("every pool that has a policy has every number that policy needs")
    func everyTierIsComplete() {
        for pool in ClipClass.allCases {
            guard let tier = ClipboardBudget.standard.tier(for: pool) else {
                #expect(pool == .kept, "only the saved clips may have no policy")
                continue
            }
            #expect(tier.bytes > 0)
            #expect(tier.items > 0)
        }
    }

    @Test("a clip is charged to exactly one pool, and saving one moves it out of the rest")
    func theTaxonomyIsTotal() {
        #expect(ClipClass(of: clip("words")) == .copied)
        #expect(ClipClass(of: clip("said", origin: .uttrflow)) == .dictation)
        #expect(
            ClipClass(
                of: Clip(
                    text: "", kind: .image, copiedAt: noon,
                    image: ClipImage(file: "a.png", width: 1, height: 1, bytes: 9))) == .images)
        // Kept beats all three, or the pictures' window would delete the pinned screenshot.
        #expect(ClipClass(of: clip("words", pinned: true)) == .kept)
        #expect(ClipClass(of: clip("said", origin: .uttrflow, alias: "/x")) == .kept)
        #expect(
            ClipClass(
                of: Clip(
                    text: "", kind: .image, copiedAt: noon,
                    image: ClipImage(file: "a.png", width: 1, height: 1, bytes: 9),
                    isPinned: true)) == .kept)
    }

    // MARK: - Nothing saved is ever taken

    /// The promise the fourth pool exists to make: saying so exempts a clip from every rule at once.
    @Test("a saved clip survives the window, the count, the memory quota and the disk")
    func savedClipsSurviveEverything() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(
            file: file.url,
            budget: .standard.limiting(items: 1, bytes: 50, days: 1, largestClip: 100, disk: 50))
        let saved = clip(String(repeating: "s", count: 40))
        try await store.record(saved, keeping: week())
        try await store.setPinned(true, of: saved.id, keeping: week())

        // Far over the count and far over the byte quota…
        for index in 0..<8 {
            try await store.record(
                clip(String(repeating: "\(index)", count: 40), usedAt: Double(index)),
                keeping: week())
        }
        // …and then asked for a month later, long past every window in the budget.
        let later = ClipRetention(days: 1, now: noon.addingTimeInterval(86_400 * 30))
        let clips = await store.clips(keeping: later)

        #expect(clips.contains { $0.id == saved.id })
        #expect(clips.filter { ClipClass(of: $0).isEvictable }.count <= 1)
    }

    // MARK: - The size cap

    /// The bound that stops growth: one copied log file is one thing.
    @Test("a clip too large to hold is refused, and costs nothing")
    func oversizedClipsAreRefused() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(largestClip: 1_000))

        try await store.record(clip("small"), keeping: week())
        let clips = try await store.record(
            clip(String(repeating: "x", count: 5_000)), keeping: week())

        #expect(clips.count == 1)
        #expect(clips.first?.text == "small")
    }

    /// Refusing it must not also throw away what was already there.
    @Test("and refusing one leaves the rest of the history alone")
    func refusingIsNotDestructive() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(largestClip: 1_000))

        try await store.record(clip("first"), keeping: week())
        try await store.record(clip("second"), keeping: week())
        _ = try await store.record(clip(String(repeating: "x", count: 5_000)), keeping: week())
        let clips = await store.clips(keeping: week())

        #expect(clips.map(\.text) == ["second", "first"])
    }

    // MARK: - Least recently used

    @Test("the quota drops what was reached for longest ago, not what arrived first")
    func evictionIsByUse() async throws {
        let file = TemporaryFile()
        // Room for two of these three.
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(bytes: 90))
        let old = clip(String(repeating: "a", count: 40), usedAt: -300)
        try await store.record(old, keeping: week())
        try await store.record(clip(String(repeating: "b", count: 40), usedAt: -200), keeping: week())

        // The oldest arrival is the most recently used, so the middle one goes.
        _ = await store.markUsed(old.id, at: noon, keeping: week())
        try await store.record(clip(String(repeating: "c", count: 40), usedAt: -100), keeping: week())
        let clips = await store.clips(keeping: week())

        #expect(clips.contains { $0.id == old.id })
        #expect(!clips.contains { $0.text.hasPrefix("b") })
    }

    @Test("and using a clip that is not there changes nothing")
    func markingAnAbsentClipIsHarmless() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        try await store.record(clip("here"), keeping: week())

        let clips = await store.markUsed(UUID(), at: noon, keeping: week())

        #expect(clips.count == 1)
    }

    // MARK: - Each pool on its own terms

    @Test("pictures age out on their own window, not the one set for words")
    func picturesHaveTheirOwnWindow() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(days: nil))
        // Ten days back: inside a thirty-day setting for words, outside the pictures' seven.
        let old = noon.addingTimeInterval(-86_400 * 10)
        try await store.record(
            Clip(
                text: "", kind: .image, copiedAt: old, origin: .copied,
                image: ClipImage(file: "a.png", width: 1, height: 1, bytes: 10, sha: "a")),
            keeping: ClipRetention(days: 30, now: noon))
        try await store.record(
            clip("words from ten days ago", usedAt: -86_400 * 10),
            keeping: ClipRetention(days: 30, now: noon))

        let clips = await store.clips(keeping: ClipRetention(days: 30, now: noon))

        #expect(clips.count == 1)
        #expect(clips.first?.kind == .text, "the words are inside the user's window")
    }

    @Test("and one pool's quota cannot evict another's")
    func poolsAreIndependent() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(items: 2))

        for index in 0..<6 {
            try await store.record(
                clip("copied \(index)", usedAt: Double(index)), keeping: week())
            try await store.record(
                clip("said \(index)", origin: .uttrflow, usedAt: Double(index)), keeping: week())
        }
        let clips = await store.clips(keeping: week())

        #expect(clips.filter { ClipClass(of: $0) == .copied }.count == 2)
        #expect(clips.filter { ClipClass(of: $0) == .dictation }.count == 2)
    }
}
