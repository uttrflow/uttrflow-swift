import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Clipboard index migration policy preserves recovery boundaries")
struct ClipMigrationTests {
    private enum Blocker: CaseIterable {
        case unreadable, unsupported, unknownFields

        func apply(to reader: inout ClipboardIndexReader, at url: URL) {
            switch self {
            case .unreadable: reader.hasUnreadableIndex = true
            case .unsupported: reader.unsupportedFormatVersions[url] = 99
            case .unknownFields: reader.unknownFieldIndexes.insert(url)
            }
        }
    }

    @Test(
        "both indexes must be readable by this schema before rewriting or sweeping",
        arguments: Blocker.allCases)
    private func readerBlockers(blocker: Blocker) throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let saved = folder.url.appending(path: "saved.json")
        var reader = ClipboardIndexReader(encryptedStore: nil)
        blocker.apply(to: &reader, at: saved)
        let answers = folder.url.appending(path: "answers.json")
        let bytes = Data("Synthetic unreadable answers.".utf8)
        try PrivateFile.write(bytes, to: answers)
        var secrecy = ClipSecrecyOverrides(file: answers, encryptedStore: nil)
        #expect(!ClipMigration.canRewriteIndexes(reader))
        #expect(!ClipMigration.indexesAreTrustworthy(reader, history: history, saved: saved))
        #expect(!ClipMigration.canReclassify(history, reader: reader, secrecy: &secrecy))
        #expect(try Data(contentsOf: answers) == bytes)
    }

    @Test("an unreplaceable index blocks migration and reclassification without broadening the read gate")
    func unreplaceableIndex() throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        var reader = ClipboardIndexReader(encryptedStore: nil)
        reader.legacyIndexes.insert(history)
        reader.unreplaceable.insert(history)
        var secrecy = ClipSecrecyOverrides(
            file: folder.url.appending(path: "answers.json"), encryptedStore: nil)
        #expect(ClipMigration.canRewriteIndexes(reader))
        #expect(!ClipMigration.canReclassify(history, reader: reader, secrecy: &secrecy))
        var writes = 0
        #expect(!ClipMigration.migrateLegacy(history, clips: [], reader: reader) { _, _ in writes += 1 })
        #expect(writes == 0)
        #expect(reader.legacyIndexes == [history])
    }

    @Test(
        "set-aside indexes block reclassification, migration and orphan sweeping", arguments: [false, true])
    func setAsideIndex(savedIsSetAside: Bool) throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let saved = folder.url.appending(path: "saved.json")
        let blocked = savedIsSetAside ? saved : history
        try PrivateFile.write(Data("Synthetic preserved index.".utf8), to: blocked)
        _ = try #require(LocalStore.setAside(blocked, now: noon))
        var reader = ClipboardIndexReader(encryptedStore: nil)
        reader.legacyIndexes.insert(blocked)
        var secrecy = ClipSecrecyOverrides(
            file: folder.url.appending(path: "answers.json"), encryptedStore: nil)
        #expect(!ClipMigration.indexesAreTrustworthy(reader, history: history, saved: saved))
        #expect(!ClipMigration.canReclassify(blocked, reader: reader, secrecy: &secrecy))
        var writes = 0
        #expect(!ClipMigration.migrateLegacy(blocked, clips: [], reader: reader) { _, _ in writes += 1 })
        #expect(writes == 0)
        #expect(reader.legacyIndexes == [blocked])
    }

    @Test("reclassification requires the persisted secrecy answers to be understood")
    func secrecyAnswers() throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        let saved = folder.url.appending(path: "saved.json")
        let answers = folder.url.appending(path: "answers.json")
        let reader = ClipboardIndexReader(encryptedStore: nil)
        var known = ClipSecrecyOverrides(file: answers, encryptedStore: nil)
        #expect(ClipMigration.canRewriteIndexes(reader))
        #expect(ClipMigration.indexesAreTrustworthy(reader, history: history, saved: saved))
        #expect(ClipMigration.canReclassify(history, reader: reader, secrecy: &known))
        try PrivateFile.write(try JSONEncoder().encode(NotSecretIndex(version: 99, digests: [])), to: answers)
        var unknown = ClipSecrecyOverrides(file: answers, encryptedStore: nil)
        #expect(!ClipMigration.canReclassify(history, reader: reader, secrecy: &unknown))
    }

    @Test("an eligible legacy upgrade filters memory-only secrets and leaves marker ownership with the actor")
    func legacyUpgrade() throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        var reader = ClipboardIndexReader(encryptedStore: nil)
        reader.legacyIndexes.insert(history)
        let visible = Clip(text: "Synthetic visible clip.", kind: .text, copiedAt: noon)
        let secret = Clip(text: "Synthetic secret clip.", kind: .secret, copiedAt: noon)
        var records: [Clip] = []
        var files: [URL] = []
        #expect(
            ClipMigration.migrateLegacy(history, clips: [visible, secret], reader: reader) { clips, file in
                records = clips
                files.append(file)
            })
        #expect(records == [visible])
        #expect(files == [history])
        #expect(reader.legacyIndexes == [history])
    }

    @Test("failed upgrades retain their legacy marker for retry")
    func legacyFailure() throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.json")
        var reader = ClipboardIndexReader(encryptedStore: nil)
        reader.legacyIndexes.insert(history)
        for failure in [ClipboardStoreError.couldNotWrite, .diskFull, .unsupportedFormat] {
            var writes = 0
            #expect(
                !ClipMigration.migrateLegacy(history, clips: [], reader: reader) {
                    _, _ throws(ClipboardStoreError) in
                    writes += 1
                    throw failure
                })
            #expect(writes == 1)
            #expect(reader.legacyIndexes == [history])
        }
        var writes = 0
        #expect(
            !ClipMigration.migrateLegacy(folder.url.appending(path: "other.json"), clips: [], reader: reader)
            {
                _, _ in writes += 1
            })
        #expect(writes == 0)
    }
}
