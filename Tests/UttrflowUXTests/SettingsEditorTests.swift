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
    @Test("warns for every Globe-key action except Do Nothing when hold-Fn is selected")
    func holdFnWarnsForEveryAssignedGlobeAction() {
        for (rawValue, title) in [
            (1, "Change Input Source"), (2, "Show Emoji & Symbols"), (3, "Start Dictation"),
        ] {
            var capabilities = SettingsCapabilities.everything
            capabilities.globeKeyAction = GlobeKeyAction(rawValue: rawValue)

            #expect(capabilities.globeKeyWarning(for: .functionHold)?.contains(title) == true)
            #expect(capabilities.globeKeyWarning(for: .controlOptionHold) == nil)
        }
        var noAction = SettingsCapabilities.everything
        noAction.globeKeyAction = GlobeKeyAction(rawValue: 0)
        #expect(noAction.globeKeyWarning(for: .functionHold) == nil)
    }

    @Test("saves a shortcut macOS would deliver")
    func acceptsDeliverable() throws {
        let binding = HotkeyBinding(keyCode: 40, modifiers: [.command, .shift])
        #expect(try applied(.shortcut(.dictate, binding)).hotkey == binding)
    }

    @Test("refuses Option plus Space and printable keys because they can type into the focused app")
    func refusesOptionCharacterShortcuts() {
        for binding in [.optionSpace, HotkeyBinding(keyCode: 0, modifiers: [.option])] {
            let reason = refusal(.shortcut(.dictate, binding))
            #expect(reason?.contains("Option") == true, "\(binding)")
            #expect(reason?.contains("type into the app") == true, "\(binding)")
        }
    }

    @Test("refuses macOS shortcuts that open system UI or change the input source")
    func refusesReservedDictateShortcuts() {
        let spotlightReason = refusal(.shortcut(.dictate, HotkeyBinding(keyCode: 49, modifiers: [.command])))
        #expect(spotlightReason?.contains("⌘Space opens Spotlight") == true)

        let shortcuts = [
            HotkeyBinding(keyCode: 49, modifiers: [.control]),
            HotkeyBinding(keyCode: 48, modifiers: [.command]),
        ]
        for binding in shortcuts {
            #expect(
                refusal(.shortcut(.dictate, binding))?.contains("Choose another Dictate shortcut") == true)
        }
    }

    @Test("keeps held modifier and Fn Dictate bindings available")
    func acceptsListenOnlyBindings() {
        #expect(refusal(.shortcut(.dictate, .controlOptionHold)) == nil)
        #expect(refusal(.shortcut(.dictate, .functionHold)) == nil)
    }

    @Test("refuses a shortcut with no modifier, and says to add one")
    func refusesBareKey() {
        let reason = refusal(.shortcut(.dictate, HotkeyBinding(keyCode: 40, modifiers: [])))
        #expect(reason?.contains("⌘") == true)
    }

    @Test("accepts F13 alone as the Dictate shortcut, which a foot switch sends")
    func acceptsTextlessKeyAlone() {
        #expect(refusal(.shortcut(.dictate, HotkeyBinding(keyCode: 105, modifiers: []))) == nil)
    }

    @Test("still refuses a letter or F5 alone with the typing reason", arguments: [UInt16(0), 96])
    func refusesTypingKeyAlone(keyCode: UInt16) {
        let reason = refusal(.shortcut(.dictate, HotkeyBinding(keyCode: keyCode, modifiers: [])))
        #expect(reason == "Hold ⌘, ⌥, ⌃ or ⇧ as well, or the shortcut would fire while you type.")
    }

    @Test("refuses F13 alone for every claimed action, and says why")
    func refusesTextlessKeyForClaimedAction() {
        let bare = HotkeyBinding(keyCode: 105, modifiers: [])
        for action: ShortcutAction in [.clipboard, .pasteLastTranscript, .copyLastTranscript] {
            #expect(refusal(.shortcut(action, bare)) == SettingsEditor.bareKeyNotClaimable, "\(action)")
        }
    }

    @Test("refuses a key code no keyboard sends")
    func refusesUndeliverableKeys() {
        // 0x80 is past the 7-bit virtual key range, so nothing can press it.
        let reason = refusal(.shortcut(.dictate, HotkeyBinding(keyCode: 0x80, modifiers: [.control])))
        #expect(reason != nil)
        #expect(reason?.contains("did not come from the keyboard") == true)
    }

    /// The sentence covers only what it can mean: a key code no keyboard sends.
    @Test("accepts a modifier combination held on its own for the observed action")
    func acceptsHeldModifierCombination() {
        // 58 is Option's own key code — what arrives when ⌃⌥ is pressed in the field.
        #expect(
            refusal(.shortcut(.dictate, HotkeyBinding(keyCode: 58, modifiers: [.control, .option]))) == nil)
    }

    /// Issue 1207: Carbon rejects a held-modifier-only combination outright, so a claimed action can never arm it.
    @Test("refuses a held modifier combination for every claimed action, and says why")
    func refusesHeldModifierCombinationForClaimedAction() {
        let heldChord = HotkeyBinding(keyCode: 58, modifiers: [.control, .option])
        for action: ShortcutAction in [.clipboard, .pasteLastTranscript, .copyLastTranscript] {
            #expect(
                refusal(.shortcut(action, heldChord)) == SettingsEditor.heldChordNotClaimable, "\(action)")
        }
    }

    @Test("refuses another action's shortcut by name without changing settings")
    func refusesDuplicateShortcut() throws {
        let settings = Settings.default
        let before = settings
        let clipboardBinding = try #require(settings.clipboardHotkey)

        #expect(throws: SettingsRejection(reason: "That is already the clipboard shortcut.")) {
            try SettingsEditor.apply(.shortcut(.dictate, clipboardBinding), to: settings)
        }

        #expect(settings == before)
    }

    @Test("refuses an incoherent binding with the registration reason")
    func refusesIncoherentBinding() {
        let binding = HotkeyBinding(keyCode: 58, modifiers: [.control])
        #expect(!binding.isCoherent)
        #expect(
            refusal(.shortcut(.dictate, binding))
                == "That combination did not register cleanly. Press and hold it again.")
    }

    /// Issue 342: ⌘C, ⌥→ and ⌥A all fired a bare-modifier binding, so the sentence has to say why and what to do.
    @Test("refuses ⌘, ⌥, ⌃ or ⇧ held on its own and caveats its Fn suggestion")
    func refusesABareModifier() {
        for binding in [
            HotkeyBinding(keyCode: 55, modifiers: [.command]),
            HotkeyBinding(keyCode: 61, modifiers: []),
            HotkeyBinding(keyCode: 59, modifiers: [.control]),
            HotkeyBinding(keyCode: 60, modifiers: [.shift]),
        ] {
            #expect(refusal(.shortcut(.dictate, binding)) == SettingsEditor.bareModifier, "\(binding)")
        }
        #expect(SettingsEditor.bareModifier.contains("Do Nothing"))
    }

    @Test("choosing a shortcut again clears the note that it was returned to its default")
    func choosingClearsTheReturnedNote() throws {
        var settings = Settings.default
        settings.shortcutsReturnedToDefault = [.dictate, .clipboard]

        let updated = try SettingsEditor.apply(.shortcut(.dictate, .functionHold), to: settings)

        #expect(updated.shortcutsReturnedToDefault == [.clipboard])
    }

    @Test("leaves the previous shortcut in force when the new one is refused")
    func previousShortcutSurvives() {
        var settings = Settings.default
        settings.hotkey = HotkeyBinding(keyCode: 40, modifiers: [.command])
        let refused = try? SettingsEditor.apply(
            .shortcut(.dictate, HotkeyBinding(keyCode: 40, modifiers: [])), to: settings)
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

    @Test("every finite period offered fits within the stored retention ceiling")
    func offeredDaysFitWithinTheCeiling() {
        #expect(SettingsRetention.finiteOfferedDays.allSatisfy { $0 <= Settings.maximumFiniteRetentionDays })
    }

    @Test("the shipped default is one of the periods on offer")
    func defaultIsOffered() {
        #expect(SettingsRetention.offeredDays.contains(Settings.defaultTranscriptRetentionDays))
    }

    @Test("offers Always first, and reads it as a word rather than a number of days")
    func alwaysComesFirst() {
        #expect(SettingsRetention.offeredDays.first == Settings.keepAlwaysDays)
        #expect(SettingsRetention.title(days: Settings.keepAlwaysDays) == "Always")
        #expect(SettingsRetention.isAlways(days: Settings.keepAlwaysDays))
        #expect(!SettingsRetention.isAlways(days: 90))
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
        #expect(normalised == [.foundationModels, .localModel, .rules])
    }

    @Test("drops kinds this build does not contain, and repeats")
    func dropsUnselectableAndDuplicates() {
        let normalised = SettingsEngines.normalised(
            [.foundationModels, .cloud, .foundationModels, .localModel])
        #expect(normalised == [.foundationModels, .localModel, .rules])
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

    @Test("writes the activation and the anchor")
    func writesTheSimpleFields() throws {
        #expect(try applied(.activation(.pressToToggle)).hotkeyActivation == .pressToToggle)
        #expect(try applied(.anchor(.rightEdge)).floatingButtonAnchor == .rightEdge)
    }

    @Test("adds a language, and ignores adding one already there")
    func addsALanguage() throws {
        let added = try applied(.spokenLanguage(.hindi, isSpoken: true))
        #expect(added.profile.preferredLanguages == [.english, .hindi])
        #expect(try applied(.spokenLanguage(.hindi, isSpoken: true), to: added) == added)
    }

    @Test("keeps how long the user pauses in the profile the pipeline adopts")
    func setsPauses() throws {
        #expect(Settings.default.profile.pauses == .usual)
        #expect(try applied(.pauses(.veryLong)).profile.pauses == .veryLong)
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
