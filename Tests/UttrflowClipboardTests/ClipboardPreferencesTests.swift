import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Clipboard privacy preferences")
struct ClipboardPreferencesTests {
    @Test("normalizes app IDs, preserves choices privately, and fails open for unknown provenance")
    func roundTripsExclusions() throws {
        var preferences = ClipboardPreferences()
        preferences.exclude("Com.Example.Secret")
        #expect(preferences.excludes("com.example.secret"))
        #expect(!preferences.excludes("com.example.other"))
        #expect(!preferences.excludes(nil))

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ClipboardPreferencesFile(
            path: ClipboardPreferencesFile.defaultFile(in: directory).path)
        try file.save(preferences)
        #expect(file.load().value == preferences)

        preferences.include("COM.EXAMPLE.SECRET")
        #expect(preferences.excludedBundleIdentifiers.isEmpty)
    }

    @Test("sets aside unreadable privacy settings and writes a valid recovery back privately")
    func unreadableSettingsCanBeRestored() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = ClipboardPreferencesFile.defaultFile(in: directory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)
        let file = ClipboardPreferencesFile(path: url.path)

        guard case .unreadable(let setAside) = file.load(), let setAside else {
            Issue.record("Unreadable clipboard settings were treated as empty.")
            return
        }
        let saved = ClipboardPreferences(excludedBundleIdentifiers: ["com.example.private"])
        try JSONEncoder().encode(saved).write(to: setAside)

        #expect(try file.restore(from: setAside) == saved)
        #expect(file.load().value == saved)
    }
}
