// Tests for reading a stored file: missing, readable, and unreadable ones set aside.

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

    @Test("Removing copies stamped before a moment keeps newer ones and any whose age is unknown.")
    func removesOnlyOlderCopies() throws {
        let root = try folder()
        let file = root.appending(path: "list.json")
        let names = [
            "list.json.unreadable-100", "list.json.unreadable-100-2", "list.json.unreadable-300",
            "list.json.unreadable-soon",
        ]
        for name in names { try Data("x".utf8).write(to: root.appending(path: name)) }
        try LocalStore.removeSetAside(file, stampedBefore: Date(timeIntervalSince1970: 200))
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(left == ["list.json.unreadable-300", "list.json.unreadable-soon"])
    }

    @Test("A folder that is not there has no copies to remove.")
    func nothingToRemove() throws {
        let file = URL.temporaryDirectory.appending(path: "uttrflow-absent-\(UUID().uuidString)/list.json")
        try LocalStore.removeSetAside(file)
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
}
