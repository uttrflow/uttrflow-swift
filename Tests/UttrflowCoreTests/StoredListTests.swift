// Tests for reading a stored file: missing, readable, and unreadable ones set aside.

import CryptoKit
import Foundation
import Testing

@testable import UttrflowCore

@Suite("Reading a stored file never loses one it could not read")
struct StoredListTests {
    /// A fresh temporary folder, so every test owns its files.
    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(
            path: "uttrflow-stored-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func isExcludedFromBackup(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        return values.isExcludedFromBackup == true
    }

    @Test("A file that is not there reads as missing, not unreadable.")
    func missing() throws {
        let file = try folder().appending(path: "list.json")
        let stored = LocalStore.read([Int].self, from: file, now: now)
        #expect(stored.value == nil)
        #expect(!stored.isUnreadable)
        #expect(!LocalStore.hasSetAside(file))
    }

    @Test("A file that decodes reads as its value and stays where it is.")
    func readable() throws {
        let file = try folder().appending(path: "list.json")
        try Data("[1,2,3]".utf8).write(to: file)
        let stored = LocalStore.read([Int].self, from: file, now: now)
        #expect(stored.value == [1, 2, 3])
        #expect(!stored.isUnreadable)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Each partial decode keeps its own original while an earlier backup exists.")
    func repeatedPartialDecodePreservesEachOriginal() throws {
        let directory = try folder()
        let file = directory.appending(path: "list.json")
        let first = Data("[1,\"first unreadable entry\"]".utf8)
        let second = Data("[2,\"second unreadable entry\"]".utf8)

        try first.write(to: file)
        #expect(LocalStore.read([Int].self, from: file, now: now).value == [1])
        try second.write(to: file)
        #expect(LocalStore.read([Int].self, from: file, now: now).value == [2])

        let copies = try LocalStore.contents(of: directory)
            .filter { $0.hasPrefix("list.json\(LocalStore.setAsideMarker)") }
            .map { try Data(contentsOf: directory.appending(path: $0)) }
        #expect(copies.count == 2)
        #expect(copies.contains(first))
        #expect(copies.contains(second))
    }

    @Test("Same-second partial decodes retain the newest backups at the set-aside limit.")
    func repeatedPartialDecodeKeepsNewestCappedCopies() throws {
        let directory = try folder()
        let file = directory.appending(path: "list.json")
        let originals = (0..<(LocalStore.setAsideLimit + 2)).map {
            Data("[\($0),\"unreadable-\($0)\"]".utf8)
        }

        for (index, original) in originals.enumerated() {
            try original.write(to: file)
            #expect(LocalStore.read([Int].self, from: file, now: now).value == [index])
        }

        let copies = try LocalStore.contents(of: directory)
            .filter { $0.hasPrefix("list.json\(LocalStore.setAsideMarker)") }
            .map { try Data(contentsOf: directory.appending(path: $0)) }
        #expect(copies.count == LocalStore.setAsideLimit)
        #expect(Set(copies) == Set(originals.suffix(LocalStore.setAsideLimit)))
    }

    @Test("A file that does not decode is moved aside with its bytes intact.")
    func undecodable() throws {
        let file = try folder().appending(path: "list.json")
        try Data("{ not json".utf8).write(to: file)
        let stored = LocalStore.read([Int].self, from: file, now: now)
        guard case .unreadable(let aside?) = stored else {
            Issue.record("expected a set-aside file, got \(stored)")
            return
        }
        #expect(stored.isUnreadable)
        #expect(stored.value == nil)
        #expect(aside.lastPathComponent == "list.json.unreadable-1800000000")
        #expect(try Data(contentsOf: aside) == Data("{ not json".utf8))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(LocalStore.hasSetAside(file))
        #expect(try isExcludedFromBackup(aside))
    }

    @Test("A cached list refuses writes only while an unreadable file is still under its own name.")
    func cachedRefusalFollowsTheFile() throws {
        let file = try folder().appending(path: "list.json")
        try Data("{ not json".utf8).write(to: file)
        var setAside = CachedStoredList<[Int]>(file: file)
        #expect(setAside.load() == nil)
        #expect(!setAside.isUnreadable)

        try Data("{ not json".utf8).write(to: file)
        var leftInPlace = CachedStoredList<[Int]>(file: file) { _ in .unreadable(setAside: nil) }
        #expect(leftInPlace.load() == nil)
        #expect(leftInPlace.isUnreadable)
    }

    @Test("A second unreadable file in the same second never replaces the first one set aside.")
    func collisions() throws {
        let file = try folder().appending(path: "list.json")
        try Data("first".utf8).write(to: file)
        _ = LocalStore.read([Int].self, from: file, now: now)
        try Data("second".utf8).write(to: file)
        guard case .unreadable(let aside?) = LocalStore.read([Int].self, from: file, now: now) else {
            Issue.record("expected a second set-aside file")
            return
        }
        #expect(aside.lastPathComponent == "list.json.unreadable-1800000000-1")
        #expect(try Data(contentsOf: aside) == Data("second".utf8))
    }

    @Test("A file that cannot be opened is set aside like one that cannot be decoded.")
    func permissionDenied() throws {
        let file = try folder().appending(path: "list.json")
        try Data("[1]".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        let stored = LocalStore.read([Int].self, from: file, now: now)
        guard case .unreadable(let aside?) = stored else {
            Issue.record("expected a set-aside file, got \(stored)")
            return
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: aside.path)
        #expect(try Data(contentsOf: aside) == Data("[1]".utf8))
    }

    @Test("A folder that refuses the rename leaves the file in place and says so.")
    func cannotSetAside() throws {
        let root = try folder()
        let file = root.appending(path: "list.json")
        try Data("{ not json".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: root.path)
        }
        guard case .unreadable(nil) = LocalStore.read([Int].self, from: file, now: now) else {
            Issue.record("expected the file to stay where it was")
            return
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Repeated failures keep only the newest set-aside copies of a file.")
    func setAsideCopiesAreCapped() throws {
        let directory = try folder()
        let file = directory.appending(path: "list.json")
        for second in 0..<(LocalStore.setAsideLimit + 2) {
            try Data("{".utf8).write(to: file)
            _ = LocalStore.read([Int].self, from: file, now: now.addingTimeInterval(Double(second)))
        }
        let copies = try LocalStore.contents(of: directory).filter { $0.hasPrefix("list.json.unreadable-") }
        #expect(copies.count == LocalStore.setAsideLimit)
        #expect(!copies.contains("list.json.unreadable-\(Int(now.timeIntervalSince1970))"))
    }

    @Test("A set-aside copy past its lifetime goes when the next one is made, and an unstamped one stays.")
    func setAsideCopiesExpire() throws {
        let directory = try folder()
        let file = directory.appending(path: "list.json")
        let expired = Int(now.timeIntervalSince1970 - LocalStore.setAsideLifetime) - 1
        try Data("old".utf8).write(to: directory.appending(path: "list.json.unreadable-\(expired)"))
        try Data("odd".utf8).write(to: directory.appending(path: "list.json.unreadable-unknown"))
        try Data("{".utf8).write(to: file)

        _ = LocalStore.read([Int].self, from: file, now: now)

        let copies = try LocalStore.contents(of: directory).sorted()
        #expect(
            copies == [
                "list.json.unreadable-\(Int(now.timeIntervalSince1970))", "list.json.unreadable-unknown",
            ])
    }

    @Test("Removing the set-aside copies takes every one of this name and nothing else.")
    func removesEveryCopy() throws {
        let root = try folder()
        let file = root.appending(path: "list.json")
        let names = ["list.json.unreadable-1", "list.json.unreadable-1-1", "list.json.unreadable-x"]
        for name in names + ["other.json.unreadable-1", "list.json"] {
            try Data("x".utf8).write(to: root.appending(path: name))
        }
        try LocalStore.removeSetAside(file)
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(left == ["list.json", "other.json.unreadable-1"])
    }

    @Test("Removing copies stamped inside a range keeps newer ones and any whose age is unknown.")
    func removesOnlyOlderCopies() throws {
        let root = try folder()
        let file = root.appending(path: "list.json")
        let names = [
            "list.json.unreadable-100", "list.json.unreadable-100-2", "list.json.unreadable-300",
            "list.json.unreadable-soon",
        ]
        for name in names { try Data("x".utf8).write(to: root.appending(path: name)) }
        try LocalStore.removeSetAside(
            file, stamped: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 200))
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(left == ["list.json.unreadable-300", "list.json.unreadable-soon"])
    }

    /// The range has a floor as well as a ceiling, so a clock that jumped cannot take an old copy with it.
    @Test("Removing copies stamped inside a range keeps one stamped before the range begins.")
    func keepsCopiesBelowTheRange() throws {
        let root = try folder()
        let file = root.appending(path: "list.json")
        for name in ["list.json.unreadable-100", "list.json.unreadable-500"] {
            try Data("x".utf8).write(to: root.appending(path: name))
        }
        try LocalStore.removeSetAside(
            file, stamped: Date(timeIntervalSince1970: 400)..<Date(timeIntervalSince1970: 600))
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(left == ["list.json.unreadable-100"])
    }

    @Test("A folder that is not there has no copies to remove.")
    func nothingToRemove() throws {
        let file = URL.temporaryDirectory.appending(path: "uttrflow-absent-\(UUID().uuidString)/list.json")
        try LocalStore.removeSetAside(file)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }

    @Test("Removing several files removes every one it can before reporting the one it could not.")
    func removeEachKeepsGoing() throws {
        let stuckFolder = try folder()
        let stuck = stuckFolder.appending(path: "stuck")
        let free = try folder().appending(path: "free")
        for file in [stuck, free] { try Data("x".utf8).write(to: file) }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: stuckFolder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stuckFolder.path)
        }
        #expect(throws: (any Error).self) { try LocalStore.removeEach([stuck, free]) }
        #expect(!FileManager.default.fileExists(atPath: free.path))
        #expect(FileManager.default.fileExists(atPath: stuck.path))
    }

    @Test("A folder that cannot be listed is a failure, not an empty folder.")
    func unlistableFolderThrows() throws {
        let root = try folder()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        #expect(throws: (any Error).self) { try LocalStore.removeSetAside(root.appending(path: "list.json")) }
    }

    private enum Origin: String, Codable, Equatable { case typed, learned }

    private struct Entry: Codable, Equatable {
        let word: String
        let origin: Origin
    }

    private let mixedList = Data(
        """
        [{"word":"Ardent","origin":"typed"},{"word":"Velmor","origin":"someFutureOrigin"},\
        {"word":"Quist","origin":"learned"}]
        """.utf8)

    @Test("Every partial read keeps the original bytes, even when another copy already exists.")
    func keepsReadableEntries() throws {
        let file = try folder().appending(path: "list.json")
        try mixedList.write(to: file)
        let stored = LocalStore.read([Entry].self, from: file, now: now)
        #expect(
            stored.value == [Entry(word: "Ardent", origin: .typed), Entry(word: "Quist", origin: .learned)])
        #expect(try Data(contentsOf: file) == mixedList)
        let aside = file.deletingLastPathComponent().appending(path: "list.json.unreadable-1800000000")
        #expect(try Data(contentsOf: aside) == mixedList)
        _ = LocalStore.read([Entry].self, from: file, now: now.addingTimeInterval(60))
        let folder = file.deletingLastPathComponent().path
        let copies = try FileManager.default.contentsOfDirectory(atPath: folder)
        #expect(copies.count == 3)
    }

    @Test("A list whose every entry decodes leaves nothing aside.")
    func readableListLeavesNothingAside() throws {
        let file = try folder().appending(path: "list.json")
        try Data(#"[{"word":"Ardent","origin":"typed"}]"#.utf8).write(to: file)
        #expect(LocalStore.read([Entry].self, from: file, now: now).value?.count == 1)
        #expect(!LocalStore.hasSetAside(file))
    }

    @Test("An encrypted list keeps the entries this build can read.")
    func encryptedKeepsReadableEntries() throws {
        let file = try folder().appending(path: "list.json")
        let store = EncryptedStore(keys: FixedKey())
        try store.write([MixedEntry.known, MixedEntry.future], to: file)
        let stored = store.read([Entry].self, from: file, now: now)
        #expect(stored.value == [Entry(word: "Ardent", origin: .typed)])
        #expect(LocalStore.hasSetAside(file))
    }

    private struct FixedKey: StoreKeyProviding {
        private static let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { Self.value }
    }

    private struct MixedEntry: Codable {
        static let known = MixedEntry(word: "Ardent", origin: "typed")
        static let future = MixedEntry(word: "Velmor", origin: "someFutureOrigin")
        let word: String
        let origin: String
    }
}
