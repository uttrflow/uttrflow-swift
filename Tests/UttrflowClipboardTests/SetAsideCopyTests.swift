// Tests that clearing and resetting the clipboard reach the copies set aside from its files.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Set-aside copies of the clipboard")
struct SetAsideCopyTests {
    /// Writes a set-aside copy of `name` into the folder, answering with where it is.
    private func copy(of name: String, in folder: borrowing TemporaryFolder) throws -> URL {
        let url = folder.url.appending(path: "\(name).unreadable-1")
        try Data("old".utf8).write(to: url)
        return url
    }

    @Test("clearing the history removes the history file's copies and keeps the saved file's")
    func clearingKeepsSavedCopies() async throws {
        let folder = try TemporaryFolder()
        let history = try copy(of: "clipboard.json", in: folder)
        let saved = try copy(of: "saved.v1.json", in: folder)
        try await folder.store.deleteEverything(keeping: folder.retention)
        #expect(!FileManager.default.fileExists(atPath: history.path))
        #expect(FileManager.default.fileExists(atPath: saved.path))
    }

    @Test("forgetting everything removes the copies of both files")
    func forgettingRemovesEveryCopy() async throws {
        let folder = try TemporaryFolder()
        let history = try copy(of: "clipboard.json", in: folder)
        let saved = try copy(of: "saved.v1.json", in: folder)
        try await folder.store.forgetEverything()
        #expect(!FileManager.default.fileExists(atPath: history.path))
        #expect(!FileManager.default.fileExists(atPath: saved.path))
    }
}
