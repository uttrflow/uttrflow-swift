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
        #expect(preferences.excludedBundleIdentifiers == ClipboardPreferences().excludedBundleIdentifiers)
    }

    @Test("ships capture off in banking and health families and their builds until the user turns it on")
    func sensitiveFamiliesShipExcluded() throws {
        var preferences = ClipboardPreferences()
        #expect(preferences.excludes("com.chase"))
        #expect(preferences.excludes("Com.Chase.Mobile.Beta"))
        #expect(preferences.excludes("com.apple.health"))
        #expect(!preferences.excludes("com.chaser"))
        #expect(!preferences.excludes("com.example.notes"))

        preferences.include("com.chase")
        #expect(!preferences.excludes("com.chase.mobile"))
        #expect(preferences.excludes("com.paypal.desktop"))

        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(ClipboardPreferences.self, from: data) == preferences)

        preferences.exclude("com.chase")
        #expect(preferences.excludes("com.chase.mobile"))
        preferences.exclude("com.example.notes")
        #expect(preferences.excludes("com.example.notes.helper"))
    }

    @Test("reads a file saved before the shipped families with those families still off")
    func olderFileKeepsFamiliesOff() throws {
        let data = Data(#"{"excludedBundleIdentifiers":[]}"#.utf8)
        let preferences = try JSONDecoder().decode(ClipboardPreferences.self, from: data)
        #expect(preferences.excludes("com.revolut.app"))
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
