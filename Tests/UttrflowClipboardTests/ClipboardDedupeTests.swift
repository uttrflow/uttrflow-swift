import Foundation
import Testing

@testable import UttrflowClipboard

/// Recording the same thing twice. Both of these were found by copying a screenshot into
/// the running app and looking at what was on disk afterwards.
@Suite("Copying something twice")
struct ClipboardDedupeTests {
    /// The behaviour that should not change: the same words twice are one clip, moved to
    /// the top, keeping the name the user gave it.
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

    /// Found in the running app: a Swift snippet copied twice came back with no language
    /// chip, and a formatted note came back plain. The clip looked identical and had been
    /// hollowed out.
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

    /// The bug this suite was written for. Every picture has an empty `text`, so matching
    /// on it made every screenshot the same clip as the last: the second replaced the
    /// first, its file was orphaned, and the surviving row pointed at neither.
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

    /// A picture clip's file is named after the clip, so a mismatch means a row is about
    /// to draw a file belonging to something else.
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

/// A clipboard is a hash map with a clock on it: the same thing copied again is that clip
/// happening once more, not another clip. What that costs, and what it buys, is a counter.
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

    /// The clock moves with the copy: retention measures from the last time somebody
    /// wanted this, which is the only reading of "kept for seven days" that survives
    /// somebody using the same address every day for a fortnight.
    @Test("the timestamp is the latest copy, not the first")
    func timestampFollowsTheLatest() async throws {
        let folder = try TemporaryFolder()
        // Both inside the retention window, or the clip the assertion is about would have
        // aged out before it could be read back.
        let now = Date()
        let old = now.addingTimeInterval(-3_600)
        _ = try await folder.store.record(
            Clip(text: "address", kind: .text, copiedAt: old), keeping: folder.retention)

        _ = try await folder.store.record(
            Clip(text: "address", kind: .text, copiedAt: now), keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).first?.copiedAt == now)
    }

    /// The change this makes possible: a screenshot copied twice used to be two clips and
    /// two files. It is one clip, one file, and a count of two.
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

    /// And the behaviour that must survive it: two *different* pictures are still two
    /// clips. Comparing the bytes is what makes both true at once.
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

    /// A store written before pictures carried a digest. Those go on never merging, which
    /// is the old behaviour, rather than the file being refused or every old screenshot
    /// collapsing into one.
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

/// The disk the history is allowed to take. Text cannot reach it; pictures reach it in a
/// thousand copies, which is the case it exists for.
@Suite("The clipboard's budget")
struct ClipboardBudgetTests {
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

    /// Least recently *used*, which is what changed. The rule was "fewest copies, then
    /// oldest", and its known weakness turned out to be the common case: the clip you have
    /// leaned on all week loses to one you copied twenty times last month and have not
    /// touched since. A repeat counts as a use, so copying something again saves it —
    /// which is the same promise the old rule was reaching for, made about the right
    /// clock.
    @Test("drops the least recently used first when the budget is exceeded")
    func evictsTheLeastRecentlyUsed() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "c.json"),
            budget: .standard.limiting(bytes: 10_000, disk: 10_000))
        let window = week(from: .now)

        try await picture(store, byte: 1, size: 4_000)  // arrives first…
        try await picture(store, byte: 2, size: 4_000)
        // …but is reached for again, so it is no longer the least recent.
        let first = try #require(
            await store.clips(keeping: window).last(where: { $0.image != nil }))
        _ = await store.markUsed(first.id, at: Date(), keeping: window)
        try await picture(store, byte: 3, size: 4_000)  // and this pushes it over

        let clips = await store.clips(keeping: window)

        #expect(clips.count == 2)
        #expect(clips.contains { $0.id == first.id }, "the one reached for most recently stays")
    }

    /// Pinning is the user saying "this one stays". A budget that overrode that would be
    /// the app deciding it knows better about the thing they deliberately kept.
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

    /// Weighs the words, and deliberately not the pictures.
    ///
    /// It used to add `image.bytes` — the size of a file on disk that the process has
    /// never read — so the figure mixed two units and the memory quota it fed was wrong by
    /// three orders of magnitude in the direction that matters. The disk is asked about
    /// separately now, where the number means what it says.
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
