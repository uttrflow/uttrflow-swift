// Tests for migration and safe refusal of clipboard payload schema versions.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Clipboard index payload versions")
struct ClipboardIndexVersionTests {
    // Fixtures are synthetic representative records, not captured user files. v26.0926.0 wrote the same bare-array shape with JSONEncoder().encode([Clip]).
    @Test("synthetic legacy history and saved fixtures decode and migrate")
    func releasedFormatMigrates() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let saved = await folder.store.savedFile
        let historyFixture = try #require(
            Bundle.module.url(forResource: "released-history-index", withExtension: "json"))
        let savedFixture = try #require(
            Bundle.module.url(forResource: "released-saved-index", withExtension: "json"))
        try Data(contentsOf: historyFixture).write(to: history)
        try Data(contentsOf: savedFixture).write(to: saved)

        let releaseFixtureRetention = ClipRetention(days: 20_000, now: folder.retention.now)
        let clips = await folder.store.clips(keeping: releaseFixtureRetention)
        #expect(Set(clips.map(\.text)) == ["Released history fixture", "Released saved fixture"])
        for url in [history, saved] {
            let migrated = try JSONDecoder().decode(
                ClipboardIndex.self, from: Data(contentsOf: url))
            #expect(migrated.version == ClipboardIndex.currentVersion)
        }
    }

    @Test("the tagged release writer's JSONEncoder bare-array shape still migrates")
    func taggedReleaseWriterShapeMigrates() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let clip = Clip(
            id: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000425")),
            text: "Synthetic release-writer proof", kind: .text, copiedAt: folder.retention.now,
            source: "Notes")
        // The v26.0926.0 persist method used this encoder call; this generated record contains no user data.
        let legacy = try JSONEncoder().encode([clip])
        #expect(try JSONDecoder().decode([Clip].self, from: legacy) == [clip])
        try legacy.write(to: history)

        let store = ClipboardStore(file: history)
        #expect(await store.clips(keeping: folder.retention).map(\.text) == [clip.text])
        #expect(try JSONDecoder().decode(ClipboardIndex.self, from: Data(contentsOf: history)).version == 2)
    }

    @Test("a future schema stays byte-for-byte untouched and refuses older-build writes")
    func futureFormatIsReadOnly() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let saved = await folder.store.savedFile
        let legacy = try Data(
            contentsOf: #require(
                Bundle.module.url(forResource: "released-history-index", withExtension: "json")))
        let copiedAt = Int(folder.retention.now.timeIntervalSinceReferenceDate)
        let future = Data(
            #"{"version":99,"clips":[{"id":"00000000-0000-4000-8000-000000000426","text":"Future clip","kind":"text","copiedAt":\#(copiedAt),"isPinned":true}],"futureField":{"keep":[1,2,3]}}"#
                .utf8)
        try legacy.write(to: history)
        try future.write(to: saved)

        let store = ClipboardStore(file: history)
        #expect(await store.clips(keeping: folder.retention).contains { $0.text == "Future clip" })
        #expect(await store.takeUnsupportedFormatVersions() == [99])
        #expect(await store.takeUnsupportedFormatVersions().isEmpty)
        await #expect(throws: ClipboardStoreError.unsupportedFormat) {
            try await store.record(
                Clip(text: "new copy", kind: .text, copiedAt: .now), keeping: folder.retention)
        }
        await #expect(throws: ClipboardStoreError.unsupportedFormat) {
            try await store.forgetEverything()
        }
        #expect(try Data(contentsOf: history) == legacy)
        #expect(try Data(contentsOf: saved) == future)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.url.path).allSatisfy {
                !$0.contains("unreadable-")
            })
    }

    @Test("a cached store refuses a future schema installed on disk before writing either index")
    func futureSchemaInstalledAfterLoadIsNotOverwritten() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let store = ClipboardStore(file: history)
        let saved = await store.savedFile
        try await store.record(
            Clip(text: "history row", kind: .text, copiedAt: .now), keeping: folder.retention)
        try await store.record(
            Clip(text: "saved row", kind: .text, copiedAt: .now, isPinned: true), keeping: folder.retention)
        _ = await store.clips(keeping: folder.retention)

        let savedBefore = try Data(contentsOf: saved)
        let future = Data(
            #"{"version":99,"clips":[{"id":"00000000-0000-4000-8000-000000000426","text":"Future clip","kind":"text","copiedAt":735000000}]}"#
                .utf8)
        try future.write(to: history)

        await #expect(throws: ClipboardStoreError.unsupportedFormat) {
            try await store.record(
                Clip(text: "new row", kind: .text, copiedAt: .now), keeping: folder.retention)
        }

        #expect(try Data(contentsOf: history) == future)
        #expect(try Data(contentsOf: saved) == savedBefore)
    }

    @Test("a future schema installed at first-load migration is not overwritten")
    func futureSchemaInstalledBeforeLegacyMigrationIsPreserved() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let clip = Clip(
            id: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000427")),
            text: "Ordinary legacy row", kind: .text, copiedAt: folder.retention.now)
        try JSONEncoder().encode([clip]).write(to: history)
        let future = Data(#"{"version":99,"clips":[],"futureField":{"keep":[4,5,6]}}"#.utf8)
        let store = ClipboardStore(file: history)

        await ClipboardStore.$beforePersistForTesting.withValue({ url in
            if url == history { try? future.write(to: url) }
        }) {
            #expect(await store.clips(keeping: folder.retention).map(\.text) == [clip.text])
        }

        #expect(try Data(contentsOf: history) == future)
        #expect(await store.takeUnsupportedFormatVersions() == [99])
        #expect(!FileManager.default.fileExists(atPath: history.appendingPathExtension("bak").path))
    }

    @Test("a cached store preserves malformed contents with a supported version")
    func malformedCurrentSchemaInstalledAfterLoadIsNotOverwritten() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let store = ClipboardStore(file: history)
        let saved = await store.savedFile
        try await store.record(
            Clip(text: "history row", kind: .text, copiedAt: .now), keeping: folder.retention)
        try await store.record(
            Clip(text: "saved row", kind: .text, copiedAt: .now, isPinned: true), keeping: folder.retention)
        _ = await store.clips(keeping: folder.retention)

        let savedBefore = try Data(contentsOf: saved)
        let malformed = Data(#"{"version":2,"futureField":{"keep":[7,8,9]}}"#.utf8)
        try malformed.write(to: history)

        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(
                Clip(text: "new row", kind: .text, copiedAt: .now), keeping: folder.retention)
        }

        #expect(try Data(contentsOf: history) == malformed)
        #expect(try Data(contentsOf: saved) == savedBefore)
    }

    @Test("a cached store preserves an undecodable legacy array")
    func malformedLegacyArrayInstalledAfterLoadIsNotOverwritten() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let store = ClipboardStore(file: history)
        try await store.record(
            Clip(text: "cached row", kind: .text, copiedAt: .now), keeping: folder.retention)
        _ = await store.clips(keeping: folder.retention)

        let malformed = Data(#"[{"id":"bad-uuid","text":"unknown legacy row"}]"#.utf8)
        try malformed.write(to: history)

        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(
                Clip(text: "new row", kind: .text, copiedAt: .now), keeping: folder.retention)
        }

        #expect(try Data(contentsOf: history) == malformed)
    }

    @Test("supported payloads with unknown fields are refused without rewriting their bytes")
    func supportedPayloadsWithUnknownFieldsAreNotOverwritten() async throws {
        let clipID = "00000000-0000-4000-8000-000000000428"
        let unknownFieldPayloads = [
            Data(
                #"{"version":2,"clips":[{"id":"\#(clipID)","text":"row","kind":"text","copiedAt":0}],"futureIndexField":true}"#
                    .utf8),
            Data(
                #"{"version":2,"clips":[{"id":"\#(clipID)","text":"row","kind":"text","copiedAt":0,"futureClipField":{"value":1}}]}"#
                    .utf8),
            Data(
                #"{"version":2,"clips":[{"id":"\#(clipID)","text":"row","kind":"image","copiedAt":0,"image":{"file":"image.png","width":1,"height":1,"bytes":1,"futureImageField":"value"}}]}"#
                    .utf8),
        ]

        for original in unknownFieldPayloads {
            let folder = try TemporaryFolder()
            let history = folder.url.appending(path: "clipboard.json")
            try original.write(to: history)
            let store = ClipboardStore(file: history)

            await #expect(throws: ClipboardStoreError.couldNotWrite) {
                try await store.record(
                    Clip(text: "new row", kind: .text, copiedAt: .now), keeping: folder.retention)
            }

            #expect(try Data(contentsOf: history) == original)
        }
    }

    @Test("legacy clips with unknown fields stay at their original path during migration")
    func legacyUnknownFieldsAreNotDiscardedByMigration() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let copiedAt = Int(folder.retention.now.timeIntervalSinceReferenceDate)
        let original = Data(
            #"[{"id":"00000000-0000-4000-8000-000000000429","text":"legacy row","kind":"text","copiedAt":\#(copiedAt),"futureClipField":{"value":1}}]"#
                .utf8)
        try original.write(to: history)
        let store = ClipboardStore(file: history)

        #expect(await store.clips(keeping: folder.retention).map(\.text) == ["legacy row"])
        #expect(try Data(contentsOf: history) == original)
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(
                Clip(text: "new row", kind: .text, copiedAt: .now), keeping: folder.retention)
        }
        #expect(try Data(contentsOf: history) == original)
    }

    @Test("a cached unknown-field index is not recreated after another process removes it")
    func unknownFieldIndexIsNotRecreatedAfterExternalRemoval() async throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let copiedAt = Int(folder.retention.now.timeIntervalSinceReferenceDate)
        let original = Data(
            #"{"version":2,"clips":[{"id":"00000000-0000-4000-8000-000000000430","text":"row","kind":"text","copiedAt":\#(copiedAt)}],"futureIndexField":{"value":1}}"#
                .utf8)
        try original.write(to: history)
        let store = ClipboardStore(file: history)

        #expect(await store.clips(keeping: folder.retention).map(\.text) == ["row"])
        try FileManager.default.removeItem(at: history)
        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(
                Clip(text: "new row", kind: .text, copiedAt: .now), keeping: folder.retention)
        }
        #expect(!FileManager.default.fileExists(atPath: history.path))
    }
}
