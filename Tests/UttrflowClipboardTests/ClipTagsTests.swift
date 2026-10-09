// Tests for a clip's tags on disk: absent when empty, kept across relaunch, and carried through every rebuild.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("A clip's tags")
struct ClipTagsTests {
    private func clip(_ text: String, tags: [String] = []) -> Clip {
        Clip(text: text, kind: .text, copiedAt: noon, source: "Notes", tags: tags)
    }

    private func fields(of clip: Clip) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip))
        return Set(try #require(object as? [String: Any]).keys)
    }

    /// An empty list written as `[]` would make every rewrite unreadable to a build from before tags.
    @Test("an untagged clip writes no tags field, and a tagged one writes a field this build knows")
    func tagsFieldOnlyWhenTagged() throws {
        #expect(try !fields(of: clip("plain")).contains("tags"))
        let tagged = try fields(of: clip("tagged", tags: ["db", "prod"]))
        #expect(tagged.contains("tags"))
        #expect(tagged.isSubset(of: Clip.persistedJSONKeys))
    }

    @Test("a clip written before tags decodes with none")
    func olderClipDecodesUntagged() throws {
        let older = try JSONEncoder().encode(clip("from an older build"))
        #expect(try JSONDecoder().decode(Clip.self, from: older).tags.isEmpty)
    }

    @Test("a tag alone keeps a clip, so retention never ages it out")
    func tagKeeps() {
        #expect(clip("tagged", tags: ["db"]).isKept)
        #expect(!clip("untagged").isKept)
    }

    @Test("a tagged clip is saved with its tags and reads back after a relaunch")
    func tagsSurviveRelaunch() async throws {
        let file = TemporaryFile()
        let subject = clip("postgres://db.example.invalid", tags: ["db", "prod"])
        try await ClipboardStore(file: file.url).record(subject, keeping: week())

        let reopened = ClipboardStore(file: file.url)
        #expect(await reopened.clips(keeping: week()).map(\.tags) == [["db", "prod"]])
        let saved = try JSONDecoder().decode(
            ClipboardIndex.self, from: Data(contentsOf: await reopened.savedFile))
        #expect(saved.clips.map(\.id) == [subject.id])
    }

    @Test("copying a tagged clip again, or editing its text, keeps its tags")
    func repeatAndEditKeepTags() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("same words", tags: ["notes"])
        try await store.record(subject, keeping: week())

        let repeated = try await store.record(clip("same words"), keeping: week())
        #expect(repeated.map(\.tags) == [["notes"]])
        let edited = try await store.setText("other words", of: subject.id, keeping: week())
        #expect(edited.map(\.tags) == [["notes"]])
    }

    @Test("undoing a delete over a newer untagged copy brings the tags back")
    func restoreBringsTagsBack() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let deleted = clip("same words", tags: ["notes"])
        try await store.record(clip("same words"), keeping: week())

        let restored = try await store.restore(deleted, keeping: week())
        #expect(restored.map(\.tags) == [["notes"]])
    }
}
