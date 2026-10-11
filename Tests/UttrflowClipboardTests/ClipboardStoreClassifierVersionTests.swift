import CryptoKit
import Foundation
import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("The clipboard detector version lives with its index")
struct ClipboardStoreClassifierVersionTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    @Test("the classifier version is inside the authenticated index envelope")
    func classifierVersionIsSealedWithIndex() async throws {
        let file = TemporaryFile()
        let encryptedStore = EncryptedStore(keys: Keys())
        let store = ClipboardStore(file: file.url, encryptedStore: encryptedStore)
        let clip = Clip(text: "copied", kind: .text, copiedAt: .now)

        try await store.record(clip, keeping: .init(days: 30, now: .now))

        #expect(EncryptedStore.isSealed(try Data(contentsOf: file.url)))
        let stored = encryptedStore.read(ClipboardIndex.self, from: file.url)
        #expect(stored.value?.classifierVersion == ClipboardIndex.currentClassifierVersion)
    }

    @Test("legacy indexes return before background classification and then persist the new version")
    func legacyIndexMigratesInBackground() async throws {
        let file = TemporaryFile()
        let old = Clip(text: "func load() { return value }", kind: .text, copiedAt: .now)
        try createParent(of: file.url)
        try JSONEncoder().encode([old]).write(to: file.url)
        let store = ClipboardStore(file: file.url)

        let first = await store.clips(keeping: .init(days: 30, now: .now))
        #expect(first.first?.kind == .text)

        await store.waitForClassifierMigrations()
        let migrated = await store.clips(keeping: .init(days: 30, now: .now))
        #expect(migrated.first?.kind == .code)
        let index = try JSONDecoder().decode(ClipboardIndex.self, from: Data(contentsOf: file.url))
        #expect(index.classifierVersion == ClipboardIndex.currentClassifierVersion)
        #expect(index.clips == migrated)
    }

    @Test("an index already judged by this detector skips launch reclassification")
    func currentVersionSkipsReclassification() async throws {
        let file = TemporaryFile()
        let clip = Clip(text: "func load() { return value }", kind: .text, copiedAt: .now)
        try createParent(of: file.url)
        try JSONEncoder().encode(ClipboardIndex(clips: [clip])).write(to: file.url)
        let store = ClipboardStore(file: file.url)

        let listed = await store.clips(keeping: .init(days: 30, now: .now))
        await store.waitForClassifierMigrations()

        #expect(listed.map(\.kind) == [.text])
        #expect(await store.clips(keeping: .init(days: 30, now: .now)).map(\.kind) == [.text])
    }

    @Test("migration advances classification without overwriting concurrent user edits")
    func migrationPreservesCurrentEdits() {
        let id = UUID()
        let snapshotClip = Clip(
            id: id, text: "func load() { return value }", kind: .text, copiedAt: .now,
            richText: "<b>original</b>")
        let currentClip = Clip(
            id: id, text: snapshotClip.text, kind: .text, copiedAt: snapshotClip.copiedAt,
            lastUsedAt: .now, lastUsedOrder: 9, richText: "<b>original</b>",
            alias: "/kept", category: "Work", isPinned: true, timesCopied: 3)
        let classified = snapshotClip.reclassified(
            as: ClipKindDetector.classification(of: snapshotClip.text))

        let result = ClipboardStore.mergeClassifierResults(
            [classified], from: [snapshotClip], into: [currentClip])

        #expect(result.coversCurrentText)
        #expect(
            result.clips == [
                currentClip.reclassified(
                    as: ClipClassification(kind: classified.kind, language: classified.language))
            ])
        #expect(result.clips.first?.kind == .code)
        #expect(result.clips.first?.alias == "/kept")
        #expect(result.clips.first?.category == "Work")
        #expect(result.clips.first?.isPinned == true)
        #expect(result.clips.first?.lastUsedOrder == 9)
        #expect(result.clips.first?.timesCopied == 3)
        #expect(result.clips.first?.richText == "<b>original</b>")
    }

    @Test("new text clips block version promotion and images retain their file")
    func migrationDoesNotPromoteUnclassifiedClipsOrChangeImages() {
        let oldClip = Clip(text: "ordinary copied text", kind: .text, copiedAt: .now)
        let classifiedOldClip = oldClip.reclassified(
            as: ClipKindDetector.classification(of: oldClip.text))
        let newClip = Clip(text: "func added() {}", kind: .text, copiedAt: .now)
        let image = Clip(
            text: "func image-placeholder() {}", kind: .image, copiedAt: .now,
            image: ClipImage(file: "retained.png", width: 1, height: 1, bytes: 4))
        let result = ClipboardStore.mergeClassifierResults(
            [classifiedOldClip], from: [oldClip, image], into: [oldClip, newClip, image])

        #expect(!result.coversCurrentText)
        #expect(result.clips[0].kind == ClipKindDetector.classification(of: oldClip.text).kind)
        #expect(result.clips[1] == newClip)
        #expect(result.clips[2] == image)
        #expect(result.clips[2].image?.file == "retained.png")
    }

    @Test("5,000 clips record synchronous legacy and versioned first-list timings")
    func firstListBenchmark() async throws {
        let now = Date.now
        let text = String(repeating: "A copied paragraph stays exactly as it was. ", count: 24)
        let clips = (0..<5_000).map { _ in
            Clip(text: text, kind: .text, copiedAt: now)
        }
        let encryptedStore = EncryptedStore(keys: Keys())
        let legacyFile = TemporaryFile()
        try encryptedStore.write(clips, to: legacyFile.url)
        let clock = ContinuousClock()
        let before = clock.now
        let decoded = encryptedStore.read([Clip].self, from: legacyFile.url).value ?? []
        let classified = decoded.map { $0.reclassified(as: ClipKindDetector.classification(of: $0.text)) }
        let beforeElapsed = before.duration(to: clock.now)

        let migrationFile = TemporaryFile()
        try encryptedStore.write(clips, to: migrationFile.url)
        let migrationStore = ClipboardStore(
            file: migrationFile.url, budget: .standard.limiting(items: 5_000),
            encryptedStore: encryptedStore)
        let after = clock.now
        let firstList = await migrationStore.clips(keeping: .init(days: 30, now: now))
        let afterElapsed = after.duration(to: clock.now)
        await migrationStore.waitForClassifierMigrations()
        let migrated = encryptedStore.read(ClipboardIndex.self, from: migrationFile.url)

        let currentFile = TemporaryFile()
        try encryptedStore.write(ClipboardIndex(clips: clips), to: currentFile.url)
        let currentStore = ClipboardStore(
            file: currentFile.url, budget: .standard.limiting(items: 5_000),
            encryptedStore: encryptedStore)
        let currentLaunch = clock.now
        let currentList = await currentStore.clips(keeping: .init(days: 30, now: now))
        let currentElapsed = currentLaunch.duration(to: clock.now)

        #expect(classified.count == 5_000)
        #expect(firstList.count == 5_000)
        #expect(migrated.value?.classifierVersion == ClipboardIndex.currentClassifierVersion)
        #expect(migrated.value?.clips.count == 5_000)
        #expect(currentList.count == 5_000)
        print(
            "Clipboard launch-to-first-list benchmark, 5,000 sealed clips: legacy decode+classification \(milliseconds(beforeElapsed)) ms; stale-version first list with background reclassification \(milliseconds(afterElapsed)) ms; current-version first list \(milliseconds(currentElapsed)) ms"
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func createParent(of url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
