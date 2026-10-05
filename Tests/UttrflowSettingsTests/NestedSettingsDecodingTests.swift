import Foundation
import Testing
import UttrflowCore
import UttrflowPredict
import UttrflowSettings

@Suite("Nested settings preserve readable choices")
struct NestedSettingsDecodingTests {
    @Test("Unknown transformers cost only their own entries, preserving preference order")
    func engineElementsDecodeIndependently() throws {
        let settings = try decode(
            #"{"engines":{"speech":"appleSpeech","transformerPreference":["rules","future",{},"foundationModels",null]}}"#
        )
        #expect(settings.engines.transformerPreference == [.rules, .foundationModels])
    }

    @Test("Invalid language elements and retired profile fields leave the readable languages intact")
    func profileElementsDecodeIndependently() throws {
        let settings = try decode(
            #"{"profile":{"profession":"Engineer","preferredLanguages":["hi","123",null,"en"],"technicalDomains":["Swift",42,"SQL"],"preferredWritingStyle":"Brief","vocabulary":["Uttrflow",{},"Codable"]}}"#
        )
        #expect(settings.profile == UserProfile(preferredLanguages: [.hindi, .english]))
    }

    @Test("Unreadable accept keys and app entries preserve other overrides, quiet mode and pause")
    func suggestionElementsDecodeIndependently() throws {
        let settings = try decode(
            #"{"suggestions":{"isEnabled":true,"turnedOff":["COM.EXAMPLE.BLOCKED",42],"turnedOn":[null,"com.example.enabled"],"chosenAcceptKeys":{"com.example.valid":"rightArrow","com.example.future":"future","com.example.null":null},"isQuiet":true,"pausedUntil":1000}}"#
        )
        #expect(
            settings.suggestions
                == SuggestionPreferences(
                    isEnabled: true, turnedOff: ["com.example.blocked"], turnedOn: ["com.example.enabled"],
                    chosenAcceptKeys: ["com.example.valid": .rightArrow], isQuiet: true,
                    pausedUntil: Date(timeIntervalSinceReferenceDate: 1000)))
    }

    @Test("Older groups keep their choices when later fields are absent")
    func missingFieldsUseTheirOwnDefaults() throws {
        let settings = try decode(
            #"{"engines":{"speech":"appleSpeech"},"profile":{"vocabulary":["Uttrflow"]},"suggestions":{"isEnabled":true,"turnedOff":["com.example.blocked"]}}"#
        )
        #expect(settings.engines.speech == .whisperKit)
        #expect(settings.engines.transformerPreference == EngineConfiguration.default.transformerPreference)
        #expect(settings.profile == .default)
        #expect(
            settings.suggestions == SuggestionPreferences(isEnabled: true, turnedOff: ["com.example.blocked"])
        )
    }

    @Test("An unreadable field defaults without discarding sibling fields")
    func unreadableFieldsUseTheirOwnDefaults() throws {
        let settings = try decode(
            #"{"engines":{"speech":7,"transformerPreference":["rules"]},"profile":{"profession":false,"preferredLanguages":42,"vocabulary":["Uttrflow"]},"suggestions":{"isEnabled":[],"isQuiet":true,"chosenAcceptKeys":[],"turnedOn":["com.example.enabled"],"pausedUntil":"later"}}"#
        )
        #expect(settings.engines == EngineConfiguration(speech: .whisperKit, transformerPreference: [.rules]))
        #expect(settings.profile == .default)
        #expect(
            settings.suggestions == SuggestionPreferences(turnedOn: ["com.example.enabled"], isQuiet: true))
    }

    @Test("Unreadable groups use their defaults", arguments: ["null", "42", "[]"])
    func unreadableGroupsUseDefaults(value: String) throws {
        let settings = try decode(
            "{\"engines\":\(value),\"profile\":\(value),\"suggestions\":\(value),\"opensAtLogin\":false}")
        #expect(settings.engines == .default)
        #expect(settings.profile == .default)
        #expect(settings.suggestions == .default)
        #expect(!settings.opensAtLogin)
    }

    @Test(
        "Present arrays preserve an empty choice and discard only unreadable elements",
        arguments: ["[]", "[null,42,{}]"])
    func readableEmptyArraysStayEmpty(value: String) throws {
        let settings = try decode(
            "{\"engines\":{\"transformerPreference\":\(value)},\"profile\":{\"preferredLanguages\":\(value)}}"
        )
        #expect(settings.engines.transformerPreference.isEmpty)
        #expect(settings.profile.preferredLanguages.isEmpty)
    }

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }
}
