import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowSettings

@Suite("The quality preset in the settings")
struct QualityPresetSettingsTests {
    private let bundle = "com.example.editor"

    @Test("a new install uses the standard preset")
    func defaultsToStandard() {
        #expect(Settings.default.qualityPreset == .standard)
        #expect(Settings.default.qualityPreset(forBundleIdentifier: bundle) == .standard)
        #expect(Settings.default.qualityPreset(forBundleIdentifier: nil) == .standard)
    }

    @Test("an app's own preset wins over the one for every app")
    func appOverrideWins() {
        let settings = Settings(
            qualityPreset: .verbatim,
            destinations: DestinationOverrides.none.setting(
                preset: .code, for: bundle, named: "Editor", fallback: .document))
        #expect(settings.qualityPreset(forBundleIdentifier: bundle) == .code)
        #expect(settings.qualityPreset(forBundleIdentifier: "com.example.other") == .verbatim)
        #expect(settings.qualityPreset(forBundleIdentifier: nil) == .verbatim)
    }

    @Test("the choice survives a save, and a file written before presets reads as standard")
    func storedForm() throws {
        let saved = try JSONEncoder().encode(Settings(qualityPreset: .code))
        #expect(try JSONDecoder().decode(Settings.self, from: saved).qualityPreset == .code)
        let older = try JSONDecoder().decode(Settings.self, from: Data(#"{"opensAtLogin":false}"#.utf8))
        #expect(older.qualityPreset == .standard)
        #expect(!older.opensAtLogin)
    }

    @Test("an unreadable preset costs only itself")
    func unreadableCostsOnlyItself() throws {
        let read = try JSONDecoder().decode(
            Settings.self, from: Data(#"{"qualityPreset":{"x":1},"opensAtLogin":false}"#.utf8))
        #expect(read.qualityPreset == .standard)
        #expect(!read.opensAtLogin)
        let unknown = try JSONDecoder().decode(
            Settings.self, from: Data(#"{"qualityPreset":"turbo","opensAtLogin":false}"#.utf8))
        #expect(unknown.qualityPreset == .standard)
    }
}
