// Tests for the two lists a clip can belong to.

import Foundation
import Testing

@testable import UttrflowClipboard

/// The two lists on the disk side; if the file keeps one stream, the tabs are only a filter over it.
@Suite("What the user copied, and what Uttrflow made")
struct ClipOriginTests {
    private func clip(
        _ text: String, origin: ClipOrigin = .copied, at offset: TimeInterval = 0
    ) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: noon.addingTimeInterval(offset),
            source: origin == .uttrflow ? ClipOrigin.dictationSource : "Notes", origin: origin)
    }

    // MARK: - A clipboard written before the two lists existed

    /// An old clip has to be placed by the only evidence left, and "everything is a ⌘C" is the wrong default.
    @Test("an old clip with no origin is placed by what its provenance says")
    func migratesFromTheProvenanceString() throws {
        let json = """
            [
              {"id":"\(UUID().uuidString)","text":"spoken","kind":"text",
               "copiedAt":0,"source":"Dictation","timesCopied":1},
              {"id":"\(UUID().uuidString)","text":"copied","kind":"text",
               "copiedAt":0,"source":"Safari","timesCopied":1},
              {"id":"\(UUID().uuidString)","text":"from nowhere","kind":"text",
               "copiedAt":0,"timesCopied":1}
            ]
            """

        let clips = try JSONDecoder().decode([Clip].self, from: Data(json.utf8))

        #expect(clips.map(\.origin) == [.uttrflow, .copied, .copied])
    }

    @Test("and a clip written since carries its own answer, whatever the provenance says")
    func decodesWhatWasWritten() throws {
        // The awkward case: an application called "Dictation" is in front when the user presses ⌘C.
        let awkward = Clip(
            text: "typed in the app called Dictation", kind: .text, copiedAt: noon,
            source: ClipOrigin.dictationSource, origin: .copied)

        let decoded = try JSONDecoder().decode(
            Clip.self, from: try JSONEncoder().encode(awkward))

        #expect(decoded.origin == .copied)
    }

    // MARK: - Two lists, not one

    /// Merging them would move a row between tabs under the user's hand.
    @Test("the same words dictated and copied are two clips")
    func sameTextInBothListsStaysTwoClips() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        try await store.record(clip("ship it on Friday", origin: .uttrflow), keeping: week())
        let clips = try await store.record(clip("ship it on Friday"), keeping: week())

        #expect(clips.count == 2)
        #expect(clips.map(\.origin) == [.copied, .uttrflow])
        #expect(clips.allSatisfy { $0.timesCopied == 1 })
    }

    @Test("but a repeat inside one list still merges, and stays in that list")
    func repeatsWithinOneListStillMerge() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        try await store.record(clip("said twice", origin: .uttrflow), keeping: week())
        let clips = try await store.record(
            clip("said twice", origin: .uttrflow, at: 60), keeping: week())

        #expect(clips.count == 1)
        #expect(clips.first?.timesCopied == 2)
        #expect(clips.first?.origin == .uttrflow)
    }

    // MARK: - Neither list can evict the other

    /// A shared cap would let a morning of dictating drop yesterday's ⌘C out of the file.
    @Test("a flood of dictations cannot push a copy out of the file")
    func theCapIsPerList() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(items: 3))

        try await store.record(clip("the one ⌘C"), keeping: week())
        for index in 0..<10 {
            try await store.record(
                clip("dictation \(index)", origin: .uttrflow, at: Double(index) + 1),
                keeping: week())
        }
        let clips = await store.clips(keeping: week())

        #expect(clips.contains { $0.text == "the one ⌘C" })
        #expect(clips.filter { $0.origin == .uttrflow }.count == 3)
        #expect(clips.filter { $0.origin == .copied }.count == 1)
    }

    @Test("and each list is capped on its own terms")
    func eachListKeepsItsOwnCapacity() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(items: 2))

        for index in 0..<4 {
            try await store.record(clip("copied \(index)", at: Double(index)), keeping: week())
            try await store.record(
                clip("said \(index)", origin: .uttrflow, at: Double(index)), keeping: week())
        }
        let clips = await store.clips(keeping: week())

        #expect(clips.filter { $0.origin == .copied }.map(\.text) == ["copied 3", "copied 2"])
        #expect(clips.filter { $0.origin == .uttrflow }.map(\.text) == ["said 3", "said 2"])
    }

    /// The count cap kept rows apart while the byte budget pooled them and evicted the cheapest first.
    @Test("copied screenshots cannot empty the list of dictations")
    func picturesInOneListCannotEvictTheOther() async throws {
        let file = TemporaryFile()
        // A megabyte, with real proportions: pictures ~100 KB, words tens of bytes.
        let store = ClipboardStore(
            file: file.url, budget: .standard.limiting(bytes: 1_000_000, disk: 1_000_000))

        for index in 0..<40 {
            try await store.record(
                clip("dictation number \(index)", origin: .uttrflow, at: Double(index)),
                keeping: week())
        }
        for index in 0..<12 {
            let picture = Clip(
                text: "", kind: .image, copiedAt: noon.addingTimeInterval(Double(index)),
                source: "Screenshot", origin: .copied,
                image: ClipImage(
                    file: "shot-\(index).png", width: 2000, height: 1200, bytes: 100_000,
                    sha: "sha-\(index)"))
            try await store.record(picture, keeping: week())
        }
        let clips = await store.clips(keeping: week())

        #expect(
            clips.filter { $0.origin == .uttrflow }.count == 40,
            "not one dictation should have been spent making room for a screenshot")
        #expect(clips.contains { $0.origin == .copied && $0.image != nil })
    }

    @Test("and the same holds the other way round")
    func picturesAreStillBoundedInsideTheirOwnList() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, budget: .standard.limiting(bytes: 500_000, disk: 500_000))

        for index in 0..<20 {
            try await store.record(clip("copied \(index)", at: Double(index)), keeping: week())
        }
        try await store.record(
            Clip(
                text: "", kind: .image, copiedAt: noon, source: "Uttrflow", origin: .uttrflow,
                image: ClipImage(
                    file: "big.png", width: 4000, height: 3000, bytes: 600_000, sha: "big")),
            keeping: week())
        let clips = await store.clips(keeping: week())

        #expect(
            clips.filter { $0.origin == .copied }.count == 20,
            "an oversized picture in one list must not be paid for out of the other")
    }

    // MARK: - Editing a clip never moves it

    /// A clip that changed tabs when tidied would vanish from under the user's hand.
    @Test("tidying a clip leaves it in the list it arrived in")
    func editsKeepTheOrigin() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)

        let spoken = clip("let us  ship  it", origin: .uttrflow)
        try await store.record(spoken, keeping: week())
        try await store.setText("let us ship it", of: spoken.id, keeping: week())
        let clips = try await store.setRichText(
            "<p>let us ship it</p>", of: spoken.id, keeping: week())

        #expect(clips.first?.origin == .uttrflow)
    }
}
