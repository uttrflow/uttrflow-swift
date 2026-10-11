// Tests that every way of deriving one clip from another carries the fields it does not change.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("A changed clip keeps every field the change does not name")
struct ClipTransformationTests {
    /// A clip with every persisted field set to something other than its default.
    private let full = Clip(
        id: UUID(), text: "let answer = 42", kind: .code, copiedAt: noon, source: "Xcode",
        origin: .uttrflow, dictations: [UUID()], dictatedText: "spoken answer",
        lastUsedAt: noon.addingTimeInterval(-10), lastUsedOrder: 8, language: .swift,
        richText: "<p>formatted note</p>",
        image: ClipImage(file: "answer.png", width: 20, height: 10, bytes: 128, sha: "digest"),
        alias: "/answer", tags: ["work", "snippets"], category: "Notes", isPinned: true,
        timesCopied: 7)

    @Test("the fixture sets every field a clip persists, so a new field must be added to it")
    func fixtureSetsEveryField() throws {
        #expect(Set(try fields(of: full).keys) == Clip.persistedJSONKeys)
    }

    @Test("using a clip changes only when it was last used")
    func used() throws {
        let later = noon.addingTimeInterval(60)
        let used = full.used(at: later, order: 12)
        try expectUnchanged(from: full, to: used, except: ["lastUsedAt", "lastUsedOrder"])
        #expect(used.lastUsedAt == later)
        #expect(used.lastUsedOrder == 12)
    }

    @Test("recopying a clip changes only when it was copied and used")
    func recopied() throws {
        let later = noon.addingTimeInterval(60)
        let recopied = full.recopied(at: later, order: 13)
        try expectUnchanged(from: full, to: recopied, except: ["copiedAt", "lastUsedAt", "lastUsedOrder"])
        #expect(recopied.copiedAt == later)
        #expect(recopied.lastUsedAt == later)
        #expect(recopied.lastUsedOrder == 13)
    }

    @Test("ordering a clip for eviction changes only its order")
    func orderedForEviction() throws {
        let ordered = full.orderedForEviction(14)
        try expectUnchanged(from: full, to: ordered, except: ["lastUsedOrder"])
        #expect(ordered.lastUsedOrder == 14)
    }

    @Test("reclassifying a clip changes only its kind and language")
    func reclassified() throws {
        let classification = ClipKindDetector.classification(of: "https://example.com")
        let reclassified = full.reclassified(as: classification)
        try expectUnchanged(from: full, to: reclassified, except: ["kind", "language"])
        #expect(reclassified.kind == classification.kind)
        #expect(reclassified.language == classification.language)
    }

    @Test("rebuilding a clip with new words keeps everything the user chose")
    func rebuilding() throws {
        let rebuilt = ClipboardStore.rebuilding(full, text: "https://example.com", richText: nil, image: nil)
        try expectUnchanged(
            from: full, to: rebuilt, except: ["text", "kind", "language", "richText", "image"])
        #expect(rebuilt.text == "https://example.com")
        #expect(rebuilt.kind == .link)
        #expect(rebuilt.richText == nil)
        #expect(rebuilt.image == nil)
    }

    @Test("relinking a clip changes only its dictations")
    func relinking() throws {
        let dictations = [UUID(), UUID()]
        let relinked = ClipboardStore.relinking(full, to: dictations)
        try expectUnchanged(from: full, to: relinked, except: ["dictations"])
        #expect(relinked.dictations == dictations)
    }

    @Test("a repeat copy keeps the earlier clip's identity and choices")
    func inheriting() throws {
        let extra = UUID()
        let arrival = Clip(
            text: "let answer = 43", kind: .text, copiedAt: noon.addingTimeInterval(30), source: "Notes",
            dictations: [extra], richText: "<p>new</p>")
        let merged = ClipboardStore.inheriting(full, from: arrival)
        try expectUnchanged(
            from: full, to: merged,
            except: [
                "text", "kind", "language", "copiedAt", "source", "dictations", "lastUsedAt", "richText",
                "timesCopied",
            ])
        #expect(merged.text == arrival.text)
        #expect(merged.copiedAt == arrival.copiedAt)
        #expect(merged.lastUsedAt == arrival.copiedAt)
        #expect(merged.source == "Notes")
        #expect(merged.dictations == full.dictations + [extra])
        #expect(merged.richText == "<p>new</p>")
        #expect(merged.timesCopied == 8)
    }

    @Test("restoring a deleted duplicate keeps every field of the newer copy it does not revive")
    func restoring() throws {
        let deletedOnly = UUID()
        let deleted = Clip(
            text: full.text, kind: .code, copiedAt: noon.addingTimeInterval(-60), dictations: [deletedOnly])
        let restored = ClipboardStore.restoring(deleted, over: full)
        try expectUnchanged(from: full, to: restored, except: ["dictations", "timesCopied"])
        #expect(restored.dictations == full.dictations + [deletedOnly])
        #expect(restored.timesCopied == 8)
    }

    private func expectUnchanged(from original: Clip, to changed: Clip, except names: Set<String>) throws {
        var before = try fields(of: original)
        var after = try fields(of: changed)
        for name in names {
            before.removeValue(forKey: name)
            after.removeValue(forKey: name)
        }
        #expect(NSDictionary(dictionary: before).isEqual(to: after))
    }

    private func fields(of clip: Clip) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
    }
}
