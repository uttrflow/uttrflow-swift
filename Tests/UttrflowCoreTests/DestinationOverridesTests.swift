import Foundation
import Testing

@testable import UttrflowCore

@Suite("An app the user treats as somewhere else")
struct DestinationOverridesTests {
    private func app(_ bundle: String, named name: String? = nil) -> AppContext {
        AppContext(applicationName: name, bundleIdentifier: bundle)
    }

    @Test("an override wins over the table")
    func overrideBeatsTheTable() {
        let slack = app("com.tinyspeck.slackmacgap", named: "Slack")
        #expect(DestinationClassifier.classify(slack) == .messaging)

        let overrides = DestinationOverrides.none.setting(
            .document, for: "com.tinyspeck.slackmacgap", named: "Slack")
        #expect(DestinationClassifier.classify(slack, overrides: overrides) == .document)
    }

    @Test("removing an override puts the table's answer back")
    func removingRestoresTheTable() {
        let slack = app("com.tinyspeck.slackmacgap")
        let overrides = DestinationOverrides.none
            .setting(.document, for: "com.tinyspeck.slackmacgap", named: "Slack")
            .removing("com.tinyspeck.slackmacgap")
        #expect(overrides.isEmpty)
        #expect(DestinationClassifier.classify(slack, overrides: overrides) == .messaging)
    }

    @Test("an app no rule names can be overridden too")
    func appWithNoRule() {
        let unknown = app("com.example.Notebook", named: "Notebook")
        #expect(DestinationClassifier.classify(unknown) == .plain)
        let overrides = DestinationOverrides.none.setting(
            .document, for: "com.example.Notebook", named: "Notebook")
        #expect(DestinationClassifier.classify(unknown, overrides: overrides) == .document)
    }

    @Test("the identifier is matched whole and without regard to case")
    func matching() {
        let overrides = DestinationOverrides.none.setting(
            .codeEditor, for: "COM.Example.Editor", named: "Editor")
        #expect(overrides.destination(for: app("com.example.editor")) == .codeEditor)
        #expect(overrides.destination(for: app("com.example.editor.helper")) == nil)
        #expect(overrides.destination(for: AppContext()) == nil)
    }

    @Test("choosing again replaces the answer rather than adding a second one")
    func replacement() {
        let overrides = DestinationOverrides.none
            .setting(.document, for: "com.example.App", named: "App")
            .setting(.email, for: "com.example.app", named: "App")
        #expect(overrides.overrides.count == 1)
        #expect(overrides.destination(forBundleIdentifier: "com.example.App") == .email)
    }

    @Test("the situation the words are going to is resolved through the overrides")
    func situation() {
        let overrides = DestinationOverrides.none.setting(
            .codeEditor, for: "com.apple.Notes", named: "Notes")
        let situation = SituationResolver.resolve(from: app("com.apple.Notes"), overrides: overrides)
        #expect(situation.destination == .codeEditor)
        #expect(SituationResolver.resolve(from: app("com.apple.Notes")).destination == .document)
    }

    @Test("the list reads in the order the names do, whatever order they were made in")
    func ordering() {
        let overrides = DestinationOverrides.none
            .setting(.document, for: "com.example.zebra", named: "Zebra")
            .setting(.document, for: "com.example.apricot", named: "Apricot")
        #expect(overrides.overrides.map(\.title) == ["Apricot", "Zebra"])
    }

    @Test("an app the screen never named is shown by its identifier")
    func unnamedApp() {
        let override = DestinationOverride(bundleIdentifier: "com.example.App", destination: .plain)
        #expect(override.title == "com.example.App")
        #expect(
            DestinationOverride(
                bundleIdentifier: "com.example.App", applicationName: "", destination: .plain
            ).title == "com.example.App")
    }

    @Test("what is stored survives a round trip and cannot hold two answers for one app")
    func roundTrip() throws {
        let overrides = DestinationOverrides.none.setting(
            .email, for: "com.example.App", named: "App")
        let data = try JSONEncoder().encode(overrides)
        #expect(try JSONDecoder().decode(DestinationOverrides.self, from: data) == overrides)

        let doubled = Data(
            """
            {"overrides":[{"bundleIdentifier":"com.example.App","destination":"email"},\
            {"bundleIdentifier":"com.example.app","destination":"document"}]}
            """.utf8)
        let decoded = try JSONDecoder().decode(DestinationOverrides.self, from: doubled)
        #expect(decoded.overrides.count == 1)
        #expect(decoded.destination(forBundleIdentifier: "com.example.app") == .email)
    }

    @Test("one entry this build has no word for costs only itself, not every other override")
    func unknownEntryKeepsTheRest() throws {
        let mixed = Data(
            """
            {"overrides":[{"bundleIdentifier":"com.example.App","destination":"email"},\
            {"bundleIdentifier":"com.example.Other","destination":"whiteboard"}]}
            """.utf8)
        let decoded = try JSONDecoder().decode(DestinationOverrides.self, from: mixed)
        #expect(decoded.overrides.count == 1)
        #expect(decoded.destination(forBundleIdentifier: "com.example.app") == .email)
    }

    @Test("a blob that says nothing this build understands is no overrides at all")
    func unreadableBlob() throws {
        #expect(
            try JSONDecoder().decode(DestinationOverrides.self, from: Data("{}".utf8)) == .none)
        #expect(
            try JSONDecoder().decode(DestinationOverrides.self, from: Data("[]".utf8)) == .none)
        #expect(
            try JSONDecoder().decode(
                DestinationOverrides.self, from: Data(#"{"overrides":7}"#.utf8)) == .none)
    }

    @Test("an override stored before modes existed reads back with its destination and mode auto")
    func migratesReleasedOverrides() throws {
        let released = Data(
            """
            {"overrides":[{"bundleIdentifier":"com.example.notes","applicationName":"Notes",\
            "destination":"email"}]}
            """.utf8)
        let decoded = try JSONDecoder().decode(DestinationOverrides.self, from: released)
        #expect(
            decoded.overrides == [
                DestinationOverride(
                    bundleIdentifier: "com.example.notes", applicationName: "Notes",
                    destination: .email, mode: .auto)
            ])
        #expect(decoded.mode(forBundleIdentifier: "com.example.notes") == .auto)
        let rewritten = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
        let original = try JSONSerialization.jsonObject(with: released)
        #expect((rewritten as? NSDictionary) == (original as? NSDictionary))
    }

    @Test(
        "each mode survives a round trip",
        arguments: [AdapterMode.auto, .prose, .forced(AdapterID(rawValue: "sql"))])
    func modeRoundTrip(mode: AdapterMode) throws {
        let overrides = DestinationOverrides([
            DestinationOverride(
                bundleIdentifier: "com.example.App", applicationName: "App", destination: .codeEditor,
                mode: mode)
        ])
        let decoded = try JSONDecoder().decode(
            DestinationOverrides.self, from: JSONEncoder().encode(overrides))
        #expect(decoded == overrides)
        #expect(decoded.mode(forBundleIdentifier: "com.example.app") == mode)
    }

    @Test("a mode this build has no word for, or a forced mode with no adapter, reads as auto")
    func unreadableModeIsAuto() throws {
        let stored = Data(
            """
            {"overrides":[{"bundleIdentifier":"com.example.App","destination":"email","mode":"later"},\
            {"bundleIdentifier":"com.example.Other","destination":"document","mode":"forced"},\
            {"bundleIdentifier":"com.example.Third","destination":"plain","mode":7}]}
            """.utf8)
        let decoded = try JSONDecoder().decode(DestinationOverrides.self, from: stored)
        #expect(decoded.overrides.count == 3)
        #expect(decoded.overrides.allSatisfy { $0.mode == .auto })
        #expect(decoded.destination(forBundleIdentifier: "com.example.other") == .document)
    }

    @Test("an app nobody overrode is auto, and choosing a destination again keeps its mode")
    func settingKeepsTheMode() {
        let forced = AdapterMode.forced(AdapterID(rawValue: "shell"))
        let overrides = DestinationOverrides([
            DestinationOverride(
                bundleIdentifier: "com.example.App", destination: .terminal, mode: forced)
        ]).setting(.codeEditor, for: "com.example.app", named: "App")
        #expect(overrides.mode(forBundleIdentifier: "com.example.App") == forced)
        #expect(overrides.destination(forBundleIdentifier: "com.example.App") == .codeEditor)
        #expect(DestinationOverrides.none.mode(forBundleIdentifier: "com.example.App") == .auto)
    }
}
