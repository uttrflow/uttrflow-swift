import Foundation
import Testing

@testable import UttrflowCore

@Suite("A final stop and first letter fixed for one app")
struct DestinationOverridePunctuationTests {
    private let bundle = "com.example.search"

    @Test("an app with nothing fixed is automatic")
    func automaticByDefault() {
        let overrides = DestinationOverrides.none.setting(.document, for: bundle, named: "Search")
        #expect(overrides.punctuation(forBundleIdentifier: bundle) == .automatic)
        #expect(DestinationOverrides.none.punctuation(forBundleIdentifier: bundle) == .automatic)
    }

    @Test("a choice outlives a change of kind, mode or preset, and they outlive a change of choice")
    func survivesOtherEdits() {
        let fixed = AppPunctuation(finalStop: .never, firstLetter: .never)
        let set = DestinationOverrides.none.setting(
            punctuation: fixed, for: bundle, named: "Search", fallback: .document)
        let moved = set.setting(.messaging, for: bundle, named: "Search")
        let formatted = moved.setting(mode: .prose, for: bundle, named: nil, fallback: .document)
        let preset = formatted.setting(preset: .verbatim, for: bundle, named: nil, fallback: .document)
        #expect(preset.punctuation(forBundleIdentifier: bundle) == fixed)
        let cleared = preset.setting(
            punctuation: .automatic, for: bundle, named: nil, fallback: .document)
        #expect(cleared.punctuation(forBundleIdentifier: bundle) == .automatic)
        #expect(cleared.destination(forBundleIdentifier: bundle) == .messaging)
        #expect(cleared.mode(forBundleIdentifier: bundle) == .prose)
        #expect(cleared.preset(forBundleIdentifier: bundle) == .verbatim)
    }

    @Test("a choice round trips, and an entry stored before choices existed decodes unchanged")
    func storedForm() throws {
        let fixed = AppPunctuation(finalStop: .never, firstLetter: .auto)
        let overrides = DestinationOverrides.none.setting(
            punctuation: fixed, for: bundle, named: "Search", fallback: .document)
        let back = try JSONDecoder().decode(DestinationOverrides.self, from: JSONEncoder().encode(overrides))
        #expect(back.punctuation(forBundleIdentifier: bundle) == fixed)

        let plain = DestinationOverrides.none.setting(.document, for: bundle, named: "Search")
        let text = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!text.contains("punctuation"))

        let old = Data(
            #"{"overrides":[{"bundleIdentifier":"com.example.old","destination":"document"}]}"#.utf8)
        let read = try JSONDecoder().decode(DestinationOverrides.self, from: old)
        #expect(read.destination(forBundleIdentifier: "com.example.old") == .document)
        #expect(read.punctuation(forBundleIdentifier: "com.example.old") == .automatic)
    }

    @Test("a choice this build has no word for reads as auto")
    func unknownWord() throws {
        let data = Data(#"{"finalStop":"sometimes","firstLetter":"never"}"#.utf8)
        let read = try JSONDecoder().decode(AppPunctuation.self, from: data)
        #expect(read == AppPunctuation(finalStop: .auto, firstLetter: .never))
    }

    @Test("the situation carries the choice into the formatter, and automatic leaves the destination's own")
    func reachesFormatter() {
        let app = AppContext(bundleIdentifier: bundle)
        let overrides = DestinationOverrides.none.setting(
            punctuation: AppPunctuation(finalStop: .never, firstLetter: .never), for: bundle,
            named: nil, fallback: .document)
        let fixed = DestinationFormatter.standard(
            for: SituationResolver.resolve(from: app, overrides: overrides))
        #expect(fixed.terminalStop == .never)
        #expect(fixed.firstWord == .asSpoken)
        let untouched = DestinationFormatter.standard(for: SituationResolver.resolve(from: app))
        #expect(untouched.terminalStop == .always)
        let stopped = DestinationOverrides.none.setting(
            punctuation: AppPunctuation(finalStop: .always), for: "com.example.term", named: nil,
            fallback: .terminal)
        let always = DestinationFormatter.standard(
            for: SituationResolver.resolve(
                from: AppContext(bundleIdentifier: "com.example.term"), overrides: stopped))
        #expect(always.destination == .terminal)
        #expect(always.terminalStop == .always)
    }
}
