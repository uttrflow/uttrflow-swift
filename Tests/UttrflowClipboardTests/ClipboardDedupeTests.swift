// Tests for copying the same thing twice, and the disk budget.

import Foundation
import Testing

@testable import UttrflowClipboard

/// Recording the same thing twice, checked against what a real screenshot copy left on disk.
@Suite("Copying something twice")
struct ClipboardDedupeTests {
    /// The same words twice are one clip, moved to the top, keeping the name the user gave it.
    @Test("the same text twice is one clip, and keeps what the user chose")
    func textStillMerges() async throws {
        let folder = try TemporaryFolder()
        let first = Clip(text: "hello", kind: .text, copiedAt: Date())
        _ = try await folder.store.record(first, keeping: folder.retention)
        _ = try await folder.store.setAlias("greeting", of: first.id, keeping: folder.retention)

        _ = try await folder.store.record(
            Clip(text: "hello", kind: .text, copiedAt: Date()), keeping: folder.retention)

        let clips = await folder.store.clips(keeping: folder.retention)
        #expect(clips.count == 1)
        #expect(clips.first?.alias == "greeting")
        #expect(clips.first?.id == first.id, "the same clip, not a replacement")
    }

    /// A clip copied twice must keep its language chip and its formatting.
    @Test("copying the same thing twice does not strip what was worked out about it")
    func mergingKeepsDerivedFields() async throws {
        let folder = try TemporaryFolder()
        let code = Clip(
            text: "struct A {}", kind: .code, copiedAt: Date(), language: .swift,
            richText: "<code>struct A {}</code>")
        _ = try await folder.store.record(code, keeping: folder.retention)

        _ = try await folder.store.record(
            Clip(
                text: "struct A {}", kind: .code, copiedAt: Date(), language: .swift,
                richText: "<code>struct A {}</code>"), keeping: folder.retention)

        let clip = try #require(await folder.store.clips(keeping: folder.retention).first)
        #expect(clip.language == .swift, "the language chip survived the second copy")
        #expect(clip.richText != nil, "and so did the formatting")
    }

    /// Every picture has an empty `text`, so matching on it made every screenshot the same clip.
    @Test("two different pictures are two clips, not one")
    func picturesDoNotCollide() async throws {
        let folder = try TemporaryFolder()

        for byte in [UInt8(0x01), UInt8(0x02)] {
            _ = try await folder.store.record(
                NoticedClip(
                    clip: Clip(text: "", kind: .image, copiedAt: Date()),
                    picture: (Data(repeating: byte, count: 128), 10, 10)),
                keeping: folder.retention)
        }

        let clips = await folder.store.clips(keeping: folder.retention)
        #expect(clips.count == 2, "one screenshot did not swallow the other")
        #expect(clips.allSatisfy { $0.image != nil }, "and both kept their picture")
    }

    /// Each clip must point at its own file, or a row draws somebody else's screenshot.
    @Test("each picture clip points at its own file, and both files are there")
    func everyPictureKeepsItsOwnFile() async throws {
        let folder = try TemporaryFolder()
        for byte in [UInt8(0x01), UInt8(0x02)] {
            _ = try await folder.store.record(
                NoticedClip(
                    clip: Clip(text: "", kind: .image, copiedAt: Date()),
                    picture: (Data(repeating: byte, count: 128), 10, 10)),
                keeping: folder.retention)
        }

        let clips = await folder.store.clips(keeping: folder.retention)
        let files = clips.compactMap(\.image?.file)
        #expect(Set(files).count == 2, "two clips, two files")
        for image in clips.compactMap(\.image) {
            #expect(await folder.store.imageData(for: image) != nil, "\(image.file) is missing")
        }
    }

    /// A picture clip's file is named after the clip, so a mismatch draws somebody else's screenshot.
    @Test("a picture's file is named after the clip that owns it")
    func fileMatchesItsClip() async throws {
        let folder = try TemporaryFolder()
        _ = try await folder.store.record(
            NoticedClip(
                clip: Clip(text: "", kind: .image, copiedAt: Date()),
                picture: (Data(repeating: 0x03, count: 64), 4, 4)),
            keeping: folder.retention)

        let clip = try #require(await folder.store.clips(keeping: folder.retention).first)
        #expect(clip.image?.file == "\(clip.id.uuidString).png")
    }
}

/// A clipboard is a hash map with a clock on it: the same thing copied again is that clip once more.
@Suite("Copying something again")
struct ClipboardRepeatTests {
    @Test("the count starts at one and rises with each repeat")
    func counts() async throws {
        let folder = try TemporaryFolder()
        for _ in 0..<3 {
            _ = try await folder.store.record(
                Clip(text: "again", kind: .text, copiedAt: Date()), keeping: folder.retention)
        }

        let clips = await folder.store.clips(keeping: folder.retention)

        #expect(clips.count == 1)
        #expect(clips.first?.timesCopied == 3)
    }

    /// Retention measures from the last time somebody wanted this, so the clock moves with the copy.
    @Test("the timestamp is the latest copy, not the first")
    func timestampFollowsTheLatest() async throws {
        let folder = try TemporaryFolder()
        // Both inside the retention window, or the clip would age out before being read back.
        let now = Date()
        let old = now.addingTimeInterval(-3_600)
        _ = try await folder.store.record(
            Clip(text: "address", kind: .text, copiedAt: old), keeping: folder.retention)

        _ = try await folder.store.record(
            Clip(text: "address", kind: .text, copiedAt: now), keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).first?.copiedAt == now)
    }

    /// A screenshot copied twice is one clip, one file, and a count of two.
    @Test("the same picture twice is one clip and one file")
    func picturesMergeOnTheirBytes() async throws {
        let folder = try TemporaryFolder()
        let bytes = Data(repeating: 7, count: 4_096)
        for _ in 0..<2 {
            _ = try await folder.store.record(
                NoticedClip(
                    clip: Clip(text: "", kind: .image, copiedAt: Date()),
                    picture: (bytes, 10, 10)),
                keeping: folder.retention)
        }

        let clips = await folder.store.clips(keeping: folder.retention)
        let files = try FileManager.default.contentsOfDirectory(
            atPath: folder.url.appending(path: "Images", directoryHint: .isDirectory).path)

        #expect(clips.count == 1)
        #expect(clips.first?.timesCopied == 2)
        #expect(files.count == 1, "the second copy wrote nothing")
    }

    /// Two different pictures are still two clips; comparing bytes makes both true at once.
    @Test("two different pictures are still two clips")
    func differentPicturesDoNotMerge() async throws {
        let folder = try TemporaryFolder()
        for byte in [UInt8(1), UInt8(2)] {
            _ = try await folder.store.record(
                NoticedClip(
                    clip: Clip(text: "", kind: .image, copiedAt: Date()),
                    picture: (Data(repeating: byte, count: 128), 10, 10)),
                keeping: folder.retention)
        }

        #expect(await folder.store.clips(keeping: folder.retention).count == 2)
    }

    /// A store written before pictures carried a digest goes on never merging them.
    @Test("pictures with no digest never merge")
    func oldPicturesWithoutADigest() {
        let old = Clip(
            text: "", kind: .image, copiedAt: Date(),
            image: ClipImage(file: "a.png", width: 1, height: 1, bytes: 1))
        let arriving = Clip(
            text: "", kind: .image, copiedAt: Date(),
            image: ClipImage(file: "b.png", width: 1, height: 1, bytes: 1))

        #expect(ClipboardStore.previous(for: arriving, in: [old]) == nil)
    }
}

/// The disk the history may take; text cannot reach it, a thousand pictures can.
@Suite("The clipboard's disk budget")
struct ClipboardDiskBudgetTests {
    private func picture(
        _ store: ClipboardStore, byte: UInt8, size: Int, copies: Int = 1
    )
        async throws
    {
        for _ in 0..<copies {
            _ = try await store.record(
                NoticedClip(
                    clip: Clip(text: "", kind: .image, copiedAt: Date()),
                    picture: (Data(repeating: byte, count: size), 10, 10)),
                keeping: week(from: .now))
        }
    }

    /// Least recently used is evicted first, and a repeat counts as a use. See Docs/clipboard-budget.md.
    @Test("drops the least recently used first when the budget is exceeded")
    func evictsTheLeastRecentlyUsed() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "c.json"),
            budget: .standard.limiting(bytes: 10_000, disk: 10_000))
        let window = week(from: .now)

        try await picture(store, byte: 1, size: 4_000)  // arrives first…
        try await picture(store, byte: 2, size: 4_000)
        // …but is reached for again, so it stops being the least recent.
        let first = try #require(
            await store.clips(keeping: window).last(where: { $0.image != nil }))
        _ = await store.markUsed(first.id, at: Date(), keeping: window)
        try await picture(store, byte: 3, size: 4_000)  // and this pushes it over

        let clips = await store.clips(keeping: window)

        #expect(clips.count == 2)
        #expect(clips.contains { $0.id == first.id }, "the one reached for most recently stays")
    }

    /// Pinning is the user saying "this one stays", and a budget must not override it.
    @Test("never drops anything the user kept")
    func pinsAreExempt() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "c.json"), budget: .standard.limiting(bytes: 5_000, disk: 5_000))
        let pinned = Clip(text: String(repeating: "p", count: 4_000), kind: .text, copiedAt: Date())
        _ = try await store.record(pinned, keeping: week(from: .now))
        _ = try await store.setPinned(true, of: pinned.id, keeping: week(from: .now))

        for index in 0..<3 {
            _ = try await store.record(
                Clip(text: String(repeating: "\(index)", count: 4_000), kind: .text, copiedAt: Date()),
                keeping: week(from: .now))
        }

        let clips = await store.clips(keeping: week(from: .now))

        #expect(clips.contains { $0.id == pinned.id })
    }

    /// Weighs the words and not the pictures, whose bytes are a file the process never reads.
    @Test("weighs what the process is actually holding: the words")
    func weight() {
        let text = Clip(text: "12345", kind: .text, copiedAt: Date())
        let picture = Clip(
            text: "", kind: .image, copiedAt: Date(),
            image: ClipImage(file: "a.png", width: 1, height: 1, bytes: 2_048))

        #expect(ClipboardStore.weight(of: text) == 5)
        #expect(ClipboardStore.weight(of: picture) == 0, "its bytes are a file, not memory")
        #expect(ClipboardStore.weight(of: [text, picture]) == 5)
    }

    /// A budget of nothing is a budget nobody set, not a clipboard that keeps nothing.
    @Test("no budget keeps everything")
    func zeroBudgetIsNoBudget() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "c.json"), budget: .standard.limiting(bytes: 0, disk: 0))

        try await picture(store, byte: 1, size: 4_000)
        try await picture(store, byte: 2, size: 4_000)

        #expect(await store.clips(keeping: week(from: .now)).count == 2)
    }
}
