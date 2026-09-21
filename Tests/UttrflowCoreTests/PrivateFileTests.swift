// Tests for the modes a local store's folders and files are written under.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("What only the owner may read")
struct PrivateFileTests {
    /// A folder under the temporary directory, removed with the test that made it.
    private struct Sandbox: ~Copyable {
        let root = URL.temporaryDirectory.appending(
            path: "uttrflow-private-\(UUID().uuidString)", directoryHint: .isDirectory)

        var file: URL { root.appending(path: "Store/kept.json", directoryHint: .notDirectory) }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @Test("makes a folder nobody else may enter")
    func directoryIsOwnerOnly() throws {
        let sandbox = Sandbox()

        try PrivateFile.makeDirectory(at: sandbox.root)

        #expect(try mode(of: sandbox.root) == PrivateFile.directoryMode)
    }

    @Test("makes every folder on the way, not only the last")
    func intermediateDirectoriesAreOwnerOnly() throws {
        let sandbox = Sandbox()
        let nested = sandbox.root.appending(path: "Store/Images", directoryHint: .isDirectory)

        try PrivateFile.makeDirectory(at: nested)

        #expect(try mode(of: nested) == PrivateFile.directoryMode)
        #expect(
            try mode(of: sandbox.root.appending(path: "Store", directoryHint: .isDirectory))
                == PrivateFile.directoryMode)
    }

    /// `createDirectory` leaves a folder that is already there as it found it, so the mode is set either way.
    @Test("tightens a folder that was already there and loose")
    func anExistingDirectoryIsTightened() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(
            at: sandbox.root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])

        try PrivateFile.makeDirectory(at: sandbox.root)

        #expect(try mode(of: sandbox.root) == PrivateFile.directoryMode)
    }

    /// Somebody who made their own folder read-only meant it, and a save is not the place to undo that.
    @Test("leaves the owner's own bits alone rather than forcing them open")
    func aStricterModeIsKept() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(
            at: sandbox.root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o500])

        try PrivateFile.makeDirectory(at: sandbox.root)

        #expect(try mode(of: sandbox.root) == 0o500)
    }

    @Test("writes a file nobody else may read, in a folder nobody else may enter")
    func writtenFileIsOwnerOnly() throws {
        let sandbox = Sandbox()

        try PrivateFile.write(Data("kept".utf8), to: sandbox.file)

        #expect(try Data(contentsOf: sandbox.file) == Data("kept".utf8))
        #expect(try mode(of: sandbox.file) == PrivateFile.fileMode)
        #expect(try mode(of: sandbox.file.deletingLastPathComponent()) == PrivateFile.directoryMode)
    }

    /// An atomic write replaces the file rather than rewriting it, so a second write is a second mode.
    @Test("tightens a file that was already there and loose")
    func anExistingFileIsTightened() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(
            at: sandbox.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: sandbox.file.path(percentEncoded: false), contents: Data("loose".utf8),
            attributes: [.posixPermissions: 0o644])

        try PrivateFile.write(Data("kept".utf8), to: sandbox.file)

        #expect(try mode(of: sandbox.file) == PrivateFile.fileMode)
    }

    /// An atomic write replaces the file, so the owner bits have to be read before it, not after.
    @Test("keeps a file's own stricter mode across a write that replaces it")
    func aStricterFileModeSurvivesAWrite() throws {
        let sandbox = Sandbox()
        try PrivateFile.write(Data("first".utf8), to: sandbox.file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o400], ofItemAtPath: sandbox.file.path(percentEncoded: false))

        try PrivateFile.write(Data("second".utf8), to: sandbox.file)

        #expect(try Data(contentsOf: sandbox.file) == Data("second".utf8))
        #expect(try mode(of: sandbox.file) == 0o400)
    }

    /// SQLite writes its own database file, and makes `-wal` and `-shm` in the mode it finds on it.
    @Test("tightens a file somebody else wrote")
    func aFileWrittenElsewhereIsTightened() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(
            at: sandbox.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: sandbox.file.path(percentEncoded: false), contents: Data(),
            attributes: [.posixPermissions: 0o644])

        try PrivateFile.tighten(at: sandbox.file)

        #expect(try mode(of: sandbox.file) == PrivateFile.fileMode)
    }

    @Test("says so rather than writing where a folder cannot be made")
    func aRefusedWriteThrows() throws {
        let sandbox = Sandbox()
        try PrivateFile.write(Data("in the way".utf8), to: sandbox.file)

        // The file just written stands where the next write wants a folder.
        #expect(throws: (any Error).self) {
            try PrivateFile.write(Data(), to: sandbox.file.appending(path: "under.json"))
        }
    }

    @Test("says so rather than tightening a file that is not there")
    func tighteningWhatIsAbsentThrows() {
        let sandbox = Sandbox()

        #expect(throws: (any Error).self) {
            try PrivateFile.tighten(at: sandbox.root.appending(path: "absent.json"))
        }
    }
}
