import Foundation
import Testing

@testable import UttrflowCore

@Suite("A quality preset chosen for one app")
struct DestinationOverridePresetTests {
    private let bundle = "com.example.editor"

    @Test("an app with no preset follows the one for every app")
    func noPresetByDefault() {
        let overrides = DestinationOverrides.none.setting(.document, for: bundle, named: "Editor")
        #expect(overrides.preset(forBundleIdentifier: bundle) == nil)
        #expect(DestinationOverrides.none.preset(forBundleIdentifier: bundle) == nil)
    }

    @Test("a preset outlives a change of kind or mode, and the kind outlives a change of preset")
    func presetSurvivesOtherEdits() {
        let set = DestinationOverrides.none.setting(
            preset: .verbatim, for: bundle, named: "Editor", fallback: .document)
        let moved = set.setting(.messaging, for: bundle, named: "Editor")
        #expect(moved.preset(forBundleIdentifier: bundle) == .verbatim)
        let formatted = moved.setting(mode: .prose, for: bundle, named: nil, fallback: .document)
        #expect(formatted.preset(forBundleIdentifier: bundle) == .verbatim)
        let cleared = formatted.setting(preset: nil, for: bundle, named: nil, fallback: .document)
        #expect(cleared.preset(forBundleIdentifier: bundle) == nil)
        #expect(cleared.destination(forBundleIdentifier: bundle) == .messaging)
        #expect(cleared.mode(forBundleIdentifier: bundle) == .prose)
    }

    @Test("a preset round trips, and an entry stored before presets reads as none")
    func storedForm() throws {
        let overrides = DestinationOverrides.none.setting(
            preset: .code, for: bundle, named: "Editor", fallback: .document)
        let back = try JSONDecoder().decode(DestinationOverrides.self, from: JSONEncoder().encode(overrides))
        #expect(back.preset(forBundleIdentifier: bundle) == .code)

        let plain = DestinationOverrides.none.setting(.document, for: bundle, named: "Editor")
        let text = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!text.contains("preset"))
    }

    @Test("an unknown or unreadable preset reads as standard and keeps the entry")
    func unknownAndUnreadable() throws {
        let unknown = Data(
            #"{"overrides":[{"bundleIdentifier":"com.example.editor","destination":"document","preset":"turbo"}]}"#
                .utf8)
        let read = try JSONDecoder().decode(DestinationOverrides.self, from: unknown)
        #expect(read.preset(forBundleIdentifier: bundle) == .standard)

        let broken = Data(
            #"{"overrides":[{"bundleIdentifier":"com.example.editor","destination":"document","preset":7}]}"#
                .utf8)
        let kept = try JSONDecoder().decode(DestinationOverrides.self, from: broken)
        #expect(kept.destination(forBundleIdentifier: bundle) == .document)
        #expect(kept.preset(forBundleIdentifier: bundle) == .standard)
    }
}
