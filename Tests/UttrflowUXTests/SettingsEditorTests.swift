import Foundation
import UttrflowCore
import UttrflowSettings
import Testing

@testable import UttrflowUX

// MARK: - Fixtures

/// A Mac that can do nothing but the floor.
private let barestMac = SettingsCapabilities(
    launchAtLogin: .unavailable,
    canPlayRecordingSound: false,
    readySpeechEngines: [],
    readyTransformers: [SettingsEngines.floor])

/// Applies a change and throws on a refusal, for changes that are setting-up rather than subject.
private func applied(
    _ change: SettingsChange,
    to settings: Settings = .default,
    given capabilities: SettingsCapabilities = .everything
) throws -> Settings {
    try SettingsEditor.apply(change, to: settings, given: capabilities)
}

/// The sentence a refused change carries, or `nil` when the change is accepted.
private func refusal(
    _ change: SettingsChange,
    to settings: Settings = .default,
    given capabilities: SettingsCapabilities = .everything
) -> String? {
    do {
        _ = try SettingsEditor.apply(change, to: settings, given: capabilities)
        return nil
    } catch {
        return error.reason
    }
}

// MARK: - Shortcut

@Suite("The shortcut cannot be saved undeliverable")
struct SettingsShortcutValidationTests {
    @Test("saves a shortcut macOS would deliver")
    func acceptsDeliverable() throws {
        let binding = HotkeyBinding(keyCode: 40, modifiers: [.command, .shift])
        #expect(try applied(.shortcut(binding)).hotkey == binding)
    }

    @Test("refuses a shortcut with no modifier, and says to add one")
    func refusesBareKey() {
        let reason = refusal(.shortcut(HotkeyBinding(keyCode: 40, modifiers: [])))
        #expect(reason?.contains("⌘") == true)
    }

    @Test("refuses a key code no keyboard sends")
    func refusesUndeliverableKeys() {
        // 0x80 is past the 7-bit virtual key range, so nothing can press it.
        let reason = refusal(.shortcut(HotkeyBinding(keyCode: 0x80, modifiers: [.control])))
        #expect(reason != nil)
        #expect(reason?.contains("did not come from the keyboard") == true)
    }

    /// The sentence covers only what it can mean: a key code no keyboard sends.
    @Test("accepts a modifier combination held on its own")
    func acceptsHeldModifierCombination() {
        // 58 is Option's own key code — what arrives when ⌃⌥ is pressed in the field.
        #expect(refusal(.shortcut(HotkeyBinding(keyCode: 58, modifiers: [.control, .option]))) == nil)
        // And a single modifier, which is the owner's choice to make even though ⌘C fires it.
        #expect(refusal(.shortcut(HotkeyBinding(keyCode: 55, modifiers: [.command]))) == nil)
    }

    @Test("leaves the previous shortcut in force when the new one is refused")
    func previousShortcutSurvives() {
        var settings = Settings.default
        settings.hotkey = HotkeyBinding(keyCode: 40, modifiers: [.command])
        let refused = try? SettingsEditor.apply(
            .shortcut(HotkeyBinding(keyCode: 40, modifiers: [])), to: settings)
        #expect(refused == nil)
        #expect(settings.hotkey == HotkeyBinding(keyCode: 40, modifiers: [.command]))
    }
}

// MARK: - Retention

@Suite("Retention offers only periods the store keeps")
struct SettingsRetentionTests {
    /// The rule lives in `Settings`, so the store is asked rather than a second copy written here.
    @Test("every offered period survives being saved and read back unchanged")
    func offeredPeriodsSurviveTheStore() throws {
        for days in SettingsRetention.offeredDays {
            var settings = Settings.default
            settings.transcriptRetentionDays = days
            let data = try JSONEncoder().encode(settings)
            let restored = try JSONDecoder().decode(Settings.self, from: data)

            #expect(restored.transcriptRetentionDays == days, "\(days) was not kept")
        }
    }

    @Test("the shipped default is one of the periods on offer")
    func defaultIsOffered() {
        #expect(SettingsRetention.offeredDays.contains(Settings.defaultRetentionDays))
    }

    @Test("refuses a period that is not on offer")
    func refusesUnofferedPeriod() {
        for days in [0, -1, 5] {
            #expect(refusal(.retention(days: days)) != nil, "\(days) was accepted")
        }
    }

    /// One period, because the transcript is the one thing a period can be about.
    @Test("sets the transcript period and nothing else")
    func setsTheTranscriptPeriod() throws {
        let settings = try applied(.retention(days: 30))
        #expect(settings.transcriptRetentionDays == 30)
        #expect(settings == Settings(transcriptRetentionDays: 30))
    }

    @Test("says one day in the singular")
    func titlesReadNaturally() {
        #expect(SettingsRetention.title(days: 1) == "1 day")
        #expect(SettingsRetention.title(days: 7) == "7 days")
    }
}

// MARK: - The clean-up floor

@Suite("The clean-up preference always ends somewhere that cannot decline")
struct SettingsEngineFloorTests {
    @Test("every level yields an order ending in the floor")
    func everyLevelEndsInTheFloor() throws {
        for level in SettingsTidyingLevel.allCases {
            let settings = try applied(.tidying(level))
            #expect(settings.engines.transformerPreference.last == SettingsEngines.floor)
            #expect(!settings.engines.resolvedTransformerPreference.isEmpty)
        }
    }

    @Test("appends the floor to an order that has none")
    func appendsMissingFloor() {
        #expect(SettingsEngines.normalised([]) == [.rules])
        #expect(SettingsEngines.normalised([.foundationModels]) == [.foundationModels, .rules])
    }

    @Test("moves a floor buried in the middle to the end")
    func movesFloorToTheEnd() {
        let normalised = SettingsEngines.normalised([.rules, .foundationModels, .localModel])
        #expect(normalised == [.foundationModels, .rules])
    }

    @Test("drops kinds this build does not contain, and repeats")
    func dropsUnselectableAndDuplicates() {
        let normalised = SettingsEngines.normalised(
            [.foundationModels, .cloud, .foundationModels, .localModel])
        #expect(normalised == [.foundationModels, .rules])
        #expect(normalised.allSatisfy(TransformerKind.selectable.contains))
    }

    @Test("standard is the full order this build can run; light is the floor alone")
    func levelsMeanWhatTheySay() {
        #expect(SettingsTidyingLevel.light.preference == [SettingsEngines.floor])
        #expect(SettingsTidyingLevel.standard.preference.count > 1)
        // The resolved preference: the raw list names a local model this build filters out.
        let shipped = EngineConfiguration.default.resolvedTransformerPreference
        #expect(SettingsTidyingLevel.standard.preference == shipped)
    }

    @Test("reads the level back out of whatever order was stored")
    func readsLevelBack() {
        #expect(SettingsTidyingLevel(preference: []) == .light)
        #expect(SettingsTidyingLevel(preference: [.rules]) == .light)
        // A cloud-only order in a build without cloud has nothing above the floor to run.
        #expect(SettingsTidyingLevel(preference: [.cloud, .rules]) == .light)
        #expect(SettingsTidyingLevel(preference: [.foundationModels, .rules]) == .standard)
    }

    @Test("a round trip through the level never loses the floor")
    func levelRoundTripKeepsTheFloor() throws {
        var settings = Settings.default
        settings.engines.transformerPreference = []
        let level = SettingsTidyingLevel(preference: settings.engines.transformerPreference)
        #expect(
            try applied(.tidying(level), to: settings).engines.transformerPreference.last
                == SettingsEngines.floor)
    }

    @Test("titles both levels")
    func levelsHaveTitles() {
        #expect(SettingsTidyingLevel.light.title == "Light")
        #expect(SettingsTidyingLevel.standard.title == "Standard")
    }
}

// MARK: - Capabilities

@Suite("A control whose capability is missing says so instead of doing nothing")
struct SettingsCapabilityTests {
    @Test("refuses the sound cue on a Mac with nothing to play it through")
    func refusesSoundWithoutOutput() {
        let reason = refusal(
            .toggle(.playsSoundWhenRecordingStarts, isOn: true), given: barestMac)
        #expect(reason?.contains("no audio output") == true)
    }

    @Test("lets the cue be turned off even when it could not be turned on")
    func offNeedsNoCapability() throws {
        var settings = Settings.default
        settings.playsSoundWhenRecordingStarts = true
        let updated = try applied(
            .toggle(.playsSoundWhenRecordingStarts, isOn: false), to: settings, given: barestMac)
        #expect(!updated.playsSoundWhenRecordingStarts)
    }

    @Test("explains each way macOS can refuse to open the app at login")
    func explainsLoginStatuses() {
        let refusals: [LaunchAtLoginStatus: Bool] = [
            .enabled: false, .disabled: false, .requiresApproval: true, .unavailable: true,
        ]
        for (status, isRefused) in refusals {
            var capabilities = SettingsCapabilities.everything
            capabilities.launchAtLogin = status
            let reason = refusal(.toggle(.opensAtLogin, isOn: true), given: capabilities)
            #expect((reason != nil) == isRefused, "\(status) was handled the wrong way round")
        }
    }

    @Test("refuses full tidying when nothing above the floor is ready")
    func refusesStandardTidyingWithoutAnEngine() {
        #expect(refusal(.tidying(.standard), given: barestMac) != nil)
        #expect(refusal(.tidying(.light), given: barestMac) == nil)
    }

    @Test("counts only engines above the floor as tidying beyond it")
    func floorAloneIsNotTidyingBeyondIt() {
        #expect(!barestMac.canTidyBeyondTheFloor)
        #expect(SettingsCapabilities.everything.canTidyBeyondTheFloor)
    }

    @Test("refuses a transcription quality whose engine is not downloaded")
    func refusesUnreadySpeechEngine() {
        var capabilities = SettingsCapabilities.everything
        capabilities.readySpeechEngines = [.appleSpeech]
        #expect(refusal(.transcription(.mostAccurate), given: capabilities) != nil)
        #expect(refusal(.transcription(.faster), given: capabilities) == nil)
    }

    @Test("will not let the grip be configured while there is no button to grip")
    func gripDependsOnTheButton() {
        var settings = Settings.default
        settings.showsFloatingButton = false
        #expect(refusal(.toggle(.shrinksToGripWhenIdle, isOn: true), to: settings) != nil)
        #expect(refusal(.toggle(.showsFloatingButton, isOn: true), to: settings) == nil)
    }
}

// MARK: - Everything else a change can be

@Suite("Applying a change")
struct SettingsChangeTests {
    @Test("writes every switch to its own field and nothing else")
    func everyToggleHasABacking() throws {
        for field in SettingsToggleField.allCases {
            var settings = Settings.default
            // Cleared first, since both switches have a dependency that is not the subject here.
            settings.showsFloatingButton = true
            settings.suggestions.isEnabled = true
            let off = try applied(.toggle(field, isOn: false), to: settings)
            #expect(!SettingsPresenter.value(of: field, in: off), "\(field) did not go off")

            let on = try applied(.toggle(field, isOn: true), to: off)
            #expect(SettingsPresenter.value(of: field, in: on), "\(field) did not come back on")
        }
    }

    @Test("writes the activation, the anchor and the transcription quality")
    func writesTheSimpleFields() throws {
        #expect(try applied(.activation(.pressToToggle)).hotkeyActivation == .pressToToggle)
        #expect(try applied(.anchor(.rightEdge)).floatingButtonAnchor == .rightEdge)
        #expect(try applied(.transcription(.faster)).engines.speech == .appleSpeech)
    }

    @Test("maps each quality to an engine and back")
    func qualityRoundTrips() {
        for quality in SettingsTranscriptionQuality.allCases {
            #expect(SettingsTranscriptionQuality(engine: quality.engine) == quality)
            #expect(!quality.title.isEmpty)
        }
    }

    @Test("adds a language, and ignores adding one already there")
    func addsALanguage() throws {
        let added = try applied(.spokenLanguage(.hindi, isSpoken: true))
        #expect(added.profile.preferredLanguages == [.english, .hindi])
        #expect(try applied(.spokenLanguage(.hindi, isSpoken: true), to: added) == added)
    }

    @Test("removes a language, but never the last one")
    func keepsAtLeastOneLanguage() throws {
        let both = try applied(.spokenLanguage(.hindi, isSpoken: true))
        let one = try applied(.spokenLanguage(.english, isSpoken: false), to: both)
        #expect(one.profile.preferredLanguages == [.hindi])

        let reason = refusal(.spokenLanguage(.hindi, isSpoken: false), to: one)
        #expect(reason?.contains("at least one language") == true)
    }

    @Test("carries the sentence the user is shown")
    func rejectionCarriesItsReason() {
        #expect(SettingsRejection(reason: "no").reason == "no")
    }
}
