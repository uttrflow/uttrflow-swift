// The user's answer to "is this a secret?" outranks the detector, in either direction.

import CryptoKit
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("The user decides whether a clip is a secret")
struct SecrecyOverrideTests {
    /// Masked by the named-secret rule although it is a model setting, the documented false positive.
    private let setting = "max_tokens: 4096"

    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    /// A copy as the watcher records it: kind decided by the detector.
    private func copied(_ text: String, at moment: Date = noon) -> Clip {
        Clip(text: text, kind: ClipKindDetector.kind(of: text), copiedAt: moment)
    }

    private func notSecretFile(beside file: URL) -> URL {
        file.deletingLastPathComponent().appending(path: LocalStoreEntry.notSecretClips.name)
    }

    @Test("a clip wrongly masked can be unmasked, and stays unmasked and pinned across a relaunch")
    func unmaskedClipSurvivesRelaunch() async throws {
        #expect(ClipKindDetector.kind(of: setting) == .secret)
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let clip = copied(setting)
        try await store.record(clip, keeping: week())
        try await store.setPinned(true, of: clip.id, keeping: week())

        let shown = try await store.setSecret(false, of: clip.id, keeping: week())

        #expect(shown.first { $0.id == clip.id }?.kind == .text)
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.map(\.text) == [setting])
        #expect(reopened.first?.kind == .text)
        #expect(reopened.first?.isPinned == true)

        // With the clip gone and the app relaunched, the same text is not masked; similar text still is.
        let relaunched = ClipboardStore(file: file.url)
        try await relaunched.delete(clip.id, keeping: week())
        let list = try await relaunched.record(copied(setting), keeping: week())
        #expect(list.first?.kind == .text)
        let other = try await relaunched.record(copied("max_tokens: 8192"), keeping: week())
        #expect(other.first?.kind == .secret)
    }

    @Test("treating a clip as a secret masks it, keeps it off the disk, and masks a repeat copy")
    func treatAsSecret() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let clip = copied("hunter-correct-staple")
        try await store.record(clip, keeping: week())
        try await store.setPinned(true, of: clip.id, keeping: week())

        let shown = try await store.setSecret(true, of: clip.id, keeping: week())

        #expect(shown.first { $0.id == clip.id }?.kind == .secret)
        #expect(await ClipboardStore(file: file.url).clips(keeping: week()).isEmpty)
        try await store.delete(clip.id, keeping: week())
        let again = try await store.record(copied("hunter-correct-staple"), keeping: week())
        #expect(again.first?.kind == .secret)
    }

    @Test("treating an unmasked text as a secret again withdraws the earlier answer")
    func treatAsSecretWithdrawsNotSecret() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let clip = copied(setting)
        try await store.record(clip, keeping: week())
        try await store.setSecret(false, of: clip.id, keeping: week())
        try await store.setSecret(true, of: clip.id, keeping: week())

        #expect(!FileManager.default.fileExists(atPath: notSecretFile(beside: file.url).path))
        let reopened = ClipboardStore(file: file.url)
        let list = try await reopened.record(copied(setting), keeping: week())
        #expect(list.first?.kind == .secret)
    }

    @Test("making a note of an unmasked clip does not mask it again")
    func editingKeepsTheAnswer() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let clip = copied(setting)
        try await store.record(clip, keeping: week())
        try await store.setSecret(false, of: clip.id, keeping: week())

        let list = try await store.setRichText("<p>\(setting)</p>", of: clip.id, keeping: week())

        #expect(list.first { $0.id == clip.id }?.kind == .text)
    }

    @Test("the answer is a sealed keyed digest, never the text, and a reset removes it")
    func sealedAndForgotten() async throws {
        let file = TemporaryFile()
        let encrypted = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let store = ClipboardStore(file: file.url, encryptedStore: encrypted)
        let clip = copied(setting)
        try await store.record(clip, keeping: week())
        try await store.setSecret(false, of: clip.id, keeping: week())

        let answers = notSecretFile(beside: file.url)
        let sealed = try Data(contentsOf: answers)
        #expect(EncryptedStore.isSealed(sealed))
        #expect(!String(decoding: sealed, as: UTF8.self).contains("max_tokens"))
        let opened = try #require(encrypted.read(NotSecretIndex.self, from: answers).value)
        let expected = try encrypted.digest(of: setting, for: ClipSecrecyOverrides.purpose)
        #expect(opened.digests == [expected])
        let reopened = ClipboardStore(file: file.url, encryptedStore: encrypted)
        #expect(await reopened.clips(keeping: week()).first?.kind == .text)

        try await reopened.forgetEverything()

        #expect(!FileManager.default.fileExists(atPath: answers.path))
        let afterReset = try await reopened.record(copied(setting), keeping: week())
        #expect(afterReset.first?.kind == .secret)
    }

    @Test("an unreadable answers file leaves stored clips as they were")
    func unreadableAnswersAreNotOverwritten() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let clip = copied(setting)
        try await store.record(clip, keeping: week())
        try await store.setSecret(false, of: clip.id, keeping: week())
        let answers = notSecretFile(beside: file.url)
        try Data("not json".utf8).write(to: answers)

        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())

        #expect(reopened.map(\.text) == [setting])
        #expect(reopened.first?.kind == .text)
    }
}
