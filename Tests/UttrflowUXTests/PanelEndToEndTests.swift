import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// Every action the panel offers, driven end to end against a real store on disk.
///
/// The unit tests each hold one decision still and check it. This does the opposite: it
/// plays whole sequences the way a person would — copy something, name it, file it, search
/// for it by the name, rename the collection, delete the clip, put it back — and asserts
/// what is actually on disk afterwards.
///
/// It exists because the bugs found in this work were nearly all *seams*. The model was
/// right and the click did not reach it; the write was right and the failure was swallowed;
/// the row was right and the panel closed before it could act. A test that only ever asks
/// one function one question cannot see any of those.
///
/// A real `ClipboardStore` over a temporary directory, never the user's own file.
@Suite("End to end, against a store on disk")
struct PanelEndToEndTests {
    /// The store, its folder, and a bound panel — torn down with the test.
    ///
    /// An ordinary value with no `deinit`, and both halves of that matter.
    ///
    /// This was a `~Copyable` struct whose `deinit` deleted the folder, and every method
    /// on it is `await`ed — so its lifetime ended at the last syntactic use rather than at
    /// the end of the test, and the deallocation landed *during* an in-flight call on the
    /// store. The symptom was a segmentation fault deep in `Sequence.first(where:)` and
    /// `seed(_:)`, over memory freed underneath them.
    ///
    /// It passed only for as long as the layout happened to be lucky: adding one unused
    /// property to `ClipboardStore` — nothing else, no behaviour at all — was enough to
    /// crash it, which is how this was found. Making it a class was not enough either;
    /// the deallocation simply moved. Nothing here now owns a lifetime that anything else
    /// depends on, and the folder is removed by the test that made it.
    struct Harness {
        let store: ClipboardStore
        let folder: URL
        let retention = ClipRetention(days: 7, now: Date())

        init() throws {
            folder = URL.temporaryDirectory.appending(
                path: "uttrflow-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            store = ClipboardStore(
                file: folder.appending(path: "clipboard.json", directoryHint: .notDirectory))
        }

        /// Called by each test through `defer`, where the point in time is written down
        /// rather than inferred from a lifetime.
        func cleanUp() { try? FileManager.default.removeItem(at: folder) }

        /// A panel over whatever the store currently holds, as the app builds one.
        func panel() async -> PanelSnapshot {
            PanelSnapshot(
                clips: await store.clips(keeping: retention), now: Date(),
                locale: Locale(identifier: "en_GB"))
        }

        /// Carries out a change exactly as `AppDelegate` does, so the test exercises the
        /// same mapping the app uses rather than a second one written for the test.
        func carryOut(_ change: PanelChange) async throws {
            switch change {
            case .setAlias(let id, let alias):
                _ = try await store.setAlias(alias, of: id, keeping: retention)
            case .setCategory(let id, let category):
                _ = try await store.setCategory(category, of: id, keeping: retention)
            case .delete(let id):
                _ = try await store.delete(id, keeping: retention)
            case .create(let text):
                _ = try await store.record(
                    Clip(text: text, kind: ClipKindDetector.kind(of: text), copiedAt: Date()),
                    keeping: retention)
            case .rewriteText(let id, let tidied):
                _ = try await store.setText(tidied, of: id, keeping: retention)
            case .setRichText(let id, let note):
                _ = try await store.setRichText(note, of: id, keeping: retention)
            case .renameCategory(let from, let to):
                for clip in await store.clips(keeping: retention) where clip.category == from {
                    _ = try await store.setCategory(to, of: clip.id, keeping: retention)
                }
            case .deleteCategory(let name, let destination):
                for clip in await store.clips(keeping: retention) where clip.category == name {
                    _ = try await store.setCategory(destination, of: clip.id, keeping: retention)
                }
            case .deleteCategoryAndClips(let name):
                for clip in await store.clips(keeping: retention) where clip.category == name {
                    _ = try await store.delete(clip.id, keeping: retention)
                }
            case .restore(let clip):
                _ = try await store.record(clip, keeping: retention)
            }
        }

        /// Applies keys to a fresh panel and carries out whatever they ask for.
        @discardableResult
        func perform(_ keys: [PanelKey]) async throws -> PanelOutcome {
            let response = await panel().applying(keys)
            if case .change(let change) = response.outcome { try await carryOut(change) }
            return response.outcome
        }

        func seed(_ texts: [String]) async throws {
            for text in texts {
                _ = try await store.record(
                    Clip(text: text, kind: ClipKindDetector.kind(of: text), copiedAt: Date()),
                    keeping: retention)
            }
        }

        func clip(_ text: String) async -> Clip? {
            await store.clips(keeping: retention).first { $0.text == text }
        }
    }

    /// The whole product, on a real store: copy three things, take the third.
    @Test("↓ ↓ Return takes the third clip, from what is actually on disk")
    func theProductLoop() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["first", "second", "third"])

        let outcome = await harness.panel().applying([.down, .down, .return]).outcome

        guard case .insert(let chosen) = outcome else {
            Issue.record("Return chose nothing")
            return
        }
        #expect(chosen.text == "first", "newest first, so two downs is the oldest of three")
    }

    /// Name it, then find it by the name — the promise the alias exists for, across a
    /// write and a re-read rather than within one snapshot.
    @Test("a name survives the write and is findable afterwards")
    func nameThenFind() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["postgres://user@prod/main", "something else"])
        let target = try #require(await harness.clip("postgres://user@prod/main"))

        try await harness.perform([.alias(target.id), .draft("/PG Prod"), .return])

        #expect(await harness.clip("postgres://user@prod/main")?.alias == "pgprod")
        // And every spelling of it resolves back to that clip.
        for typed in ["pgprod", "/pgprod", "PG PROD", "pg prod"] {
            let outcome = await harness.panel().applying([.search(typed), .return]).outcome
            guard case .insert(let found) = outcome else {
                Issue.record("“\(typed)” found nothing")
                return
            }
            #expect(found.id == target.id, "“\(typed)” found the wrong clip")
        }
    }

    @Test("filing a clip, then renaming the collection, keeps the clip and its name")
    func fileThenRename() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["a note"])
        let target = try #require(await harness.clip("a note"))

        try await harness.perform([.alias(target.id), .draft("note"), .return])
        try await harness.perform([.move(target.id), .draft("Work"), .return])
        #expect(await harness.clip("a note")?.category == "Work")

        try await harness.perform([.renameCategory("Work"), .draft("Projects"), .return])

        let after = try #require(await harness.clip("a note"))
        #expect(after.category == "Projects")
        #expect(after.alias == "note", "a collection is a shelf, not part of the clip")
    }

    /// F7 and F9 across a real write: gone from disk, and back again with everything the
    /// user had chosen about it.
    @Test("delete removes it from disk, and undo restores it whole")
    func deleteThenUndo() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["keep me"])
        var target = try #require(await harness.clip("keep me"))
        try await harness.perform([.alias(target.id), .draft("keeper"), .return])
        try await harness.perform([.move(target.id), .draft("Work"), .return])
        target = try #require(await harness.clip("keep me"))

        // A kept clip asks first, so the delete is the confirmation's answer.
        let asked = await harness.panel().applying(.delete(target.id))
        #expect(asked.state.sheet == .confirmingDelete(target.id))
        try await harness.carryOut(.delete(target.id))
        #expect(await harness.clip("keep me") == nil)

        try await harness.carryOut(.restore(target))

        let back = try #require(await harness.clip("keep me"))
        #expect(back.alias == "keeper")
        #expect(back.category == "Work")
    }

    /// G6 — the clips are moved out, not orphaned and not destroyed.
    @Test("deleting a collection keeps its clips when asked to")
    func deleteCollectionKeepingClips() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["one", "two"])
        for text in ["one", "two"] {
            let clip = try #require(await harness.clip(text))
            try await harness.perform([.move(clip.id), .draft("Work"), .return])
        }

        try await harness.perform([.deleteCategory("Work"), .return])

        let clips = await harness.store.clips(keeping: harness.retention)
        #expect(clips.count == 2, "nothing was deleted")
        #expect(clips.allSatisfy { $0.category == nil }, "and nothing was left orphaned")
    }

    @Test("or deletes them with it, when that is what was chosen")
    func deleteCollectionAndClips() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["one", "two", "elsewhere"])
        for text in ["one", "two"] {
            let clip = try #require(await harness.clip(text))
            try await harness.perform([.move(clip.id), .draft("Work"), .return])
        }

        var panel = await harness.panel()
        panel.sheet = .deletingCategory("Work", keepingClips: false)
        if case .change(let change) = panel.applying(.return).outcome {
            try await harness.carryOut(change)
        }

        let clips = await harness.store.clips(keeping: harness.retention)
        #expect(clips.map(\.text) == ["elsewhere"], "only the collection's clips went")
    }

    /// H3 — the text of a fruitless search becomes a clip, and is then findable.
    @Test("keeping a search that found nothing makes it a clip")
    func keepTheQuery() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["nothing relevant"])

        let page = PanelPresenter.present(await harness.panel().applying(.search("pgprod")).state)
        guard case .keepQuery(let text)? = page.emptyAction?.intent else {
            Issue.record("nothing offered")
            return
        }
        try await harness.carryOut(.create(text))

        #expect(await harness.clip("pgprod") != nil)
    }

    /// D4 across a write: the indentation changes, the content does not, and everything
    /// the user chose about the clip survives.
    @Test("re-indenting rewrites only the whitespace, and keeps the clip's identity")
    func reindentKeepsEverything() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let messy = "func a() {\n\tlet x = 1\n        let y = 2\n}"
        try await harness.seed([messy])
        var target = try #require(await harness.clip(messy))
        try await harness.perform([.alias(target.id), .draft("snippet"), .return])
        target = try #require(await harness.clip(messy))

        try await harness.perform([.reindent(target.id)])

        let clips = await harness.store.clips(keeping: harness.retention)
        let after = try #require(clips.first { $0.id == target.id })
        #expect(after.text != messy, "something changed")
        #expect(
            messy.split(separator: "\n").map { $0.drop { $0 == " " || $0 == "\t" } }
                == after.text.split(separator: "\n").map { $0.drop { $0 == " " || $0 == "\t" } },
            "and it was only the indentation")
        #expect(after.alias == "snippet")
        #expect(clips.count == 1, "one clip, not a second copy of it")
    }

    /// Every write goes through the store, so a sequence of them has to leave one
    /// coherent file rather than the last one winning.
    @Test("a long sequence of actions leaves the store consistent")
    func aLongSequence() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try await harness.seed(["alpha", "beta", "gamma", "delta"])

        for (text, name) in [("alpha", "a"), ("beta", "b"), ("gamma", "c")] {
            let clip = try #require(await harness.clip(text))
            try await harness.perform([.alias(clip.id), .draft(name), .return])
            try await harness.perform([.move(clip.id), .draft("Work"), .return])
        }
        let doomed = try #require(await harness.clip("delta"))
        try await harness.carryOut(.delete(doomed.id))

        let clips = await harness.store.clips(keeping: harness.retention)
        #expect(clips.count == 3)
        #expect(Set(clips.compactMap(\.alias)) == ["a", "b", "c"])
        #expect(clips.allSatisfy { $0.category == "Work" })

        // And the panel built over that file agrees with it.
        let panel = await harness.panel()
        #expect(panel.categories == ["Work"])
        #expect(panel.applying(.search("b")).state.results.rows.first?.clip.alias == "b")
    }
}
