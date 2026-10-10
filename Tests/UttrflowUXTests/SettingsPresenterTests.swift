import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowPredict
import UttrflowSettings
import Testing

@testable import UttrflowUX

// MARK: - Fixtures

/// Every pane a fully capable Mac draws, swept over every state the counts can be in.
private func everyPane(
    _ settings: Settings = .default,
    _ capabilities: SettingsCapabilities = .everything
) -> [SettingsPane] {
    SettingsPersonalisationFixtures.every.flatMap { personalisation in
        SettingsTab.allCases.map {
            SettingsPresenter.pane(
                for: $0, settings: settings, capabilities: capabilities,
                personalisation: personalisation)
        }
    }
}

extension SettingsPane {
    fileprivate var everyRow: [SettingsRow] { groups.flatMap(\.rows) }

    fileprivate func row(_ id: String) -> SettingsRow? {
        everyRow.first { $0.id == id }
    }

    /// Every word this pane would put in front of the user.
    fileprivate var everyString: [String] {
        var strings = [title]
        strings += [banner?.title, banner?.message, callout?.message].compactMap(\.self)
        strings += groups.compactMap(\.title)
        for row in everyRow {
            strings += [row.label, row.explanation, row.unavailability].compactMap(\.self)
            switch row.control {
            case .segmented(let options, _), .menu(let options, _):
                strings += options.map(\.title)
            case .shortcut(_, let keys):
                strings += keys
            case .removal(let removal):
                strings += [removal.title]
                strings += [
                    removal.confirmation?.title, removal.confirmation?.message,
                    removal.confirmation?.confirmTitle, removal.confirmation?.cancelTitle,
                ].compactMap(\.self)
            case .action(let title, _):
                strings += [title]
            case .text(let value), .placeholder(let value), .status(let value):
                strings += [value]
            case .languages(let chips, let add):
                strings += chips.map(\.title) + add.map(\.title)
            case .toggle, .tick, .applicationSwitch:
                break
            }
        }
        return strings
    }
}

// MARK: - The window

@Suite("The Settings window")
struct SettingsWindowTests {
    @Test("has a sidebar entry for every tab that exists")
    func everyTabIsInTheSidebar() {
        let items = SettingsPresenter.tabs()
        #expect(items.map(\.tab) == SettingsTab.allCases)
        for item in items {
            #expect(!item.title.isEmpty, "\(item.tab) has no title")
            #expect(!item.symbolName.isEmpty, "\(item.tab) has no symbol")
            #expect(item.id == item.tab)
        }
        #expect(items.first { $0.tab == .suggestions }?.badge == BetaFeature.label)
        #expect(items.first { $0.tab == .dictation }?.badge == nil)
        #expect(
            SettingsPresenter.pane(for: .general, settings: .default)
                .row(SettingsToggleField.clipboardEnabled.rawValue)?.badge == BetaFeature.label)
        #expect(
            SettingsPresenter.pane(for: .suggestions, settings: .default)
                .row(SettingsToggleField.suggestionsEnabled.rawValue)?.badge == BetaFeature.label)
    }

    @Test("shows the tab it was asked for, alongside the whole sidebar")
    func windowShowsTheRequestedTab() {
        for tab in SettingsTab.allCases {
            let window = SettingsPresenter.window(showing: tab, settings: .default)
            #expect(window.selected == tab)
            #expect(window.pane.tab == tab)
            #expect(window.tabs.count == SettingsTab.allCases.count)
        }
    }

    @Test("draws something on every tab but Diagnostics, whose content is the diagnostics page")
    func noTabIsEmpty() {
        for pane in everyPane() where pane.tab != .diagnostics {
            #expect(!pane.title.isEmpty, "\(pane.tab) has no title")
            #expect(!pane.groups.isEmpty, "\(pane.tab) has no cards")
            #expect(!pane.everyRow.isEmpty, "\(pane.tab) has no rows")
        }
    }

    @Test("gives every group and every row an identity of its own")
    func identitiesAreUnique() {
        for pane in everyPane() {
            let groupIDs = pane.groups.map(\.id)
            #expect(Set(groupIDs).count == groupIDs.count, "\(pane.tab) repeats a group id")
            let rowIDs = pane.everyRow.map(\.id)
            #expect(Set(rowIDs).count == rowIDs.count, "\(pane.tab) repeats a row id")
        }
    }

    @Test("every choice on offer is selectable, and one of them is selected")
    func selectionsAreReal() {
        for pane in everyPane() {
            for row in pane.everyRow {
                switch row.control {
                case .segmented(let options, let selected), .menu(let options, let selected):
                    #expect(!options.isEmpty, "\(row.id) offers nothing")
                    #expect(
                        options.map(\.id).contains(selected),
                        "\(row.id) has selected something it does not offer")
                    #expect(Set(options.map(\.id)).count == options.count)
                case .toggle, .shortcut, .tick, .removal, .action, .text, .placeholder, .status, .languages,
                    .applicationSwitch:
                    break
                }
            }
        }
    }

    /// §16: the user chooses how much help they want, never which implementation gives it.
    @Test("never names an engine, a model or a file")
    func neverNamesAnEngine() {
        let forbidden = [
            "whisper", "foundationmodels", "apple intelligence", "mlx", "llm", "gpt",
            "transformer", "model", "engine", ".swift", "rules",
        ]
        for pane in everyPane() {
            for string in pane.everyString {
                let lowered = string.lowercased()
                for word in forbidden {
                    #expect(!lowered.contains(word), "\(pane.tab) says '\(word)' in: \(string)")
                }
            }
        }
    }
}

@Suite("Accept key guidance")
struct SettingsAcceptKeyGuidanceTests {
    @Test("warns only for a known category when Tab is selected")
    func collisionCategoriesAndPlainText() throws {
        var settings = Settings.default
        settings.suggestions.set("com.apple.Terminal", isOn: true)
        settings.suggestions.set("com.apple.dt.Xcode", isOn: true)
        settings.suggestions.set("com.tinyapp.TablePlus", isOn: true)
        settings.suggestions.set("com.microsoft.Excel", isOn: true)
        settings.suggestions.set("com.apple.Notes", isOn: true)
        settings.suggestions.set("com.example.unknown", isOn: true)
        settings.suggestions.setAcceptKey(.tab, in: "com.apple.Terminal")
        settings.suggestions.setAcceptKey(.tab, in: "com.apple.dt.Xcode")
        settings.suggestions.setAcceptKey(.tab, in: "com.tinyapp.TablePlus")
        settings.suggestions.setAcceptKey(.tab, in: "com.microsoft.Excel")
        settings.suggestions.setAcceptKey(.tab, in: "com.apple.Notes")
        settings.suggestions.setAcceptKey(.tab, in: "com.example.unknown")

        let pane = SettingsPresenter.pane(for: .suggestions, settings: settings)
        func explanation(_ bundleIdentifier: String) throws -> String? {
            let identifier = bundleIdentifier.lowercased()
            return try #require(
                pane.groups.flatMap(\.rows).first {
                    $0.id == "suggestionAcceptKey.\(identifier)"
                }
            ).explanation
        }
        #expect(
            try explanation("com.apple.Terminal") == "Tab accepts suggestions instead of shell completion.")
        #expect(
            try explanation("com.apple.dt.Xcode")
                == "Tab accepts suggestions instead of indentation and editor completion.")
        #expect(
            try explanation("com.tinyapp.TablePlus")
                == "Tab accepts suggestions instead of indentation and SQL completion.")
        #expect(
            try explanation("com.microsoft.Excel") == "Tab accepts suggestions instead of cell navigation.")
        #expect(
            try explanation("com.apple.Notes")
                == "Tab accepts suggestions instead of the notes app's own behavior.")
        #expect(try explanation("com.example.unknown") == nil)
    }

    @Test("describes the selected key for this app and explains the Right arrow Escape behavior")
    func alternateKeyDescriptionsFitTheApplication() throws {
        var settings = Settings.default
        settings.suggestions.set("com.apple.Terminal", isOn: true)
        settings.suggestions.set("com.apple.dt.Xcode", isOn: true)
        settings.suggestions.set("com.apple.Notes", isOn: true)
        settings.suggestions.set("com.example.unknown", isOn: true)
        settings.suggestions.setAcceptKey(.rightArrow, in: "com.apple.Terminal")
        settings.suggestions.setAcceptKey(.rightArrow, in: "com.apple.Notes")
        settings.suggestions.setAcceptKey(.optionTab, in: "com.apple.dt.Xcode")
        settings.suggestions.setAcceptKey(.optionTab, in: "com.example.unknown")

        let pane = SettingsPresenter.pane(for: .suggestions, settings: settings)
        let rows = Dictionary(uniqueKeysWithValues: pane.groups.flatMap(\.rows).map { ($0.id, $0) })
        #expect(
            rows["suggestionAcceptKey.com.apple.terminal"]?.explanation
                == "Leaves Tab to the shell's own completion. Escape will not dismiss suggestions.")
        #expect(
            rows["suggestionAcceptKey.com.apple.dt.xcode"]?.explanation
                == "Leaves Tab to indentation and editor completion.")
        #expect(
            rows["suggestionAcceptKey.com.apple.notes"]?.explanation
                == "Leaves Tab to the notes app's own behavior. Escape will not dismiss suggestions.")
        #expect(
            rows["suggestionAcceptKey.com.example.unknown"]?.explanation
                == "Leaves Tab available in this app.")
    }
}

// MARK: - General

@Suite("The General tab")
struct SettingsGeneralPaneTests {
    private func general(
        _ settings: Settings = .default, _ capabilities: SettingsCapabilities = .everything
    ) -> SettingsPane {
        SettingsPresenter.pane(for: .general, settings: settings, capabilities: capabilities)
    }

    @Test("offers pause and resume from the current capture state")
    func clipboardPauseActionFollowsState() throws {
        let paused = try #require(general().row("clipboard-pause"))
        #expect(
            paused.control
                == .action(
                    title: "Pause for 1 hour", change: .pauseClipboardCapture(isOn: true)))
        var capabilities = SettingsCapabilities.everything
        capabilities.clipboardCapturePaused = true
        let resumed = try #require(general(.default, capabilities).row("clipboard-pause"))
        #expect(
            resumed.control
                == .action(
                    title: "Resume", change: .pauseClipboardCapture(isOn: false)))
    }

    @Test("shows the shortcut in force on keycaps")
    func showsTheShortcut() {
        var settings = Settings.default
        settings.hotkey = HotkeyBinding(keyCode: 40, modifiers: [.command])
        #expect(
            general(settings).row("shortcut.dictate")?.control
                == .shortcut(action: .dictate, keys: ["⌘", "K"]))
    }

    /// Issue 353: the Dictate row showed one cap, ⌥, for a shortcut of ⌃⌥⌘ held together.
    @Test("shows every modifier of a shortcut made only of modifiers")
    func showsAModifierChord() {
        var settings = Settings.default
        settings.hotkey = HotkeyBinding(keyCode: 58, modifiers: [.option, .command, .control])
        settings.clipboardHotkey = .shiftCommandV
        #expect(
            general(settings).row("shortcut.dictate")?.control
                == .shortcut(action: .dictate, keys: ["⌃", "⌥", "⌘"]))
        #expect(
            general(settings).row("shortcut.clipboard")?.control
                == .shortcut(action: .clipboard, keys: ["⇧", "⌘", "V"]))
    }

    @Test("explains the Dictate shortcut for the selected activation mode")
    func explainsDictateActivation() throws {
        var settings = Settings.default
        let hold = try #require(general(settings).row("shortcut.dictate")?.explanation)
        #expect(hold == "Hold ⌃⌥ to talk, anywhere")

        settings.hotkeyActivation = .pressToToggle
        let toggle = try #require(general(settings).row("shortcut.dictate")?.explanation)
        #expect(toggle == "Press ⌃⌥ once to start talking, and again to stop")
        #expect(!toggle.lowercased().contains("double"))
    }

    @Test("keeps the Fn explanation ahead of the selected activation mode")
    func functionHoldExplanationTakesPrecedence() throws {
        var settings = Settings.default
        settings.hotkey = .functionHold
        settings.hotkeyActivation = .pressToToggle

        let explanation = try #require(general(settings).row("shortcut.dictate")?.explanation)
        #expect(explanation.contains("If pressing fn also opens Emoji"))
        #expect(!explanation.contains("once to start talking"))
    }

    @Test("offers both ways of activating, with the stored one selected")
    func offersBothActivations() {
        var settings = Settings.default
        settings.hotkeyActivation = .pressToToggle
        guard
            case .segmented(let options, let selected)? = general(settings).row("activation")?
                .control
        else {
            Issue.record("the activation row is not a segmented control")
            return
        }
        #expect(options.map(\.change) == HotkeyActivation.allCases.map(SettingsChange.activation))
        #expect(selected == HotkeyActivation.pressToToggle.rawValue)
    }

    @Test("offers every place the floating button can park, with the stored one selected")
    func showsTheAnchor() {
        var settings = Settings.default
        settings.floatingButtonAnchor = .bottomLeft
        guard case .menu(let options, let selected) = general(settings).row("anchor")?.control else {
            Issue.record("the position is not a pop-up")
            return
        }
        #expect(selected == DockAnchor.bottomLeft.rawValue)
        #expect(options.map(\.title) == ["Bottom left", "Bottom centre", "Bottom right", "Right edge"])
        #expect(options.map(\.change) == DockAnchor.allCases.map { .anchor($0) })
    }

    @Test("turns off what depends on the floating button, and says why")
    func hidingTheButtonDisablesWhatDependsOnIt() {
        var settings = Settings.default
        settings.showsFloatingButton = false
        let pane = general(settings)

        for id in ["anchor", SettingsToggleField.shrinksToGripWhenIdle.rawValue] {
            let row = pane.row(id)
            #expect(row?.isEnabled == false, "\(id) is still operable with no button")
            #expect(row?.unavailability?.isEmpty == false, "\(id) gives no reason")
        }
        // Minimising is about the main window, not the button, so it stays operable.
        #expect(pane.row(SettingsToggleField.minimisesWhileDictating.rawValue)?.isEnabled == true)
        #expect(pane.row(SettingsToggleField.showsFloatingButton.rawValue)?.isEnabled == true)
    }

    @Test("says why the sound cue cannot be turned on")
    func explainsAMissingSoundCue() {
        var capabilities = SettingsCapabilities.everything
        capabilities.canPlayRecordingSound = false
        let row = general(.default, capabilities)
            .row(SettingsToggleField.playsSoundWhenRecordingStarts.rawValue)
        #expect(row?.isEnabled == false)
        #expect(row?.unavailability?.contains("no audio output") == true)
    }

    @Test("says why macOS will not open the app at login")
    func explainsAMissingLoginItem() {
        var capabilities = SettingsCapabilities.everything
        capabilities.launchAtLogin = .unavailable
        let row = general(.default, capabilities).row(SettingsToggleField.opensAtLogin.rawValue)
        #expect(row?.isEnabled == false)
        #expect(row?.unavailability?.isEmpty == false)
    }

    @Test("shows every switch reading the field behind it")
    func switchesFollowTheirFields() {
        var settings = Settings.default
        settings.showsFloatingButton = true
        settings.shrinksToGripWhenIdle = false
        settings.minimisesWhileDictating = false
        settings.playsSoundWhenRecordingStarts = false
        settings.opensAtLogin = false

        for row in general(settings).everyRow {
            guard case .toggle(let field, let isOn) = row.control else { continue }
            #expect(isOn == SettingsPresenter.value(of: field, in: settings), "\(field) is wrong")
            #expect(row.id == field.rawValue)
        }
    }

    @Test("every switch on this screen has a row")
    func noSwitchIsForgotten() {
        let fields = everyPane().flatMap(\.everyRow).compactMap { row -> SettingsToggleField? in
            guard case .toggle(let field, _) = row.control else { return nil }
            return field
        }
        #expect(Set(fields) == Set(SettingsToggleField.allCases))
    }
}

// MARK: - Languages

@Suite("The Languages tab")
struct SettingsLanguagesPaneTests {
    private func languages(_ settings: Settings = .default) -> SettingsPane {
        SettingsPresenter.pane(for: .languages, settings: settings, capabilities: .everything)
    }

    @Test("shows the languages the user speaks as chips and offers the rest to add")
    func chipsWhatIsSpoken() {
        var settings = Settings.default
        settings.profile.preferredLanguages = [.english, .hindi]

        #expect(
            languages(settings).row("spokenLanguages")?.control
                == .languages(
                    chips: [
                        SettingsChip(
                            id: "en", title: "English", removal: .spokenLanguage(.english, isSpoken: false)),
                        SettingsChip(
                            id: "hi", title: "Hindi", removal: .spokenLanguage(.hindi, isSpoken: false)),
                    ],
                    add: []))

        settings.profile.preferredLanguages = [.hindi]
        guard case .languages(_, let add) = languages(settings).row("spokenLanguages")?.control else {
            Issue.record("the languages are not chips")
            return
        }
        #expect(
            add == [
                SettingsOption(id: "en", title: "English", change: .spokenLanguage(.english, isSpoken: true))
            ])
    }

    @Test("offers how long the user pauses beside the languages, with usual pauses chosen to begin with")
    func offersPauses() {
        #expect(
            languages().row("pauses")?.control
                == .segmented(
                    options: [
                        SettingsOption(id: "usual", title: "Usual", change: .pauses(.usual)),
                        SettingsOption(id: "long", title: "Long", change: .pauses(.long)),
                        SettingsOption(id: "veryLong", title: "Very long", change: .pauses(.veryLong)),
                    ],
                    selectedID: "usual"))
    }

    @Test("offers no way to remove the only language the user has, rather than refusing it afterwards")
    func theLastLanguageCannotBeUntangled() {
        guard case .languages(let chips, _) = languages().row("spokenLanguages")?.control else {
            Issue.record("the languages are not chips")
            return
        }
        #expect(chips.map(\.title) == ["English"])
        #expect(chips.allSatisfy { $0.removal == nil })
    }

    @Test("shows the tidying example as the shipped rules write it, under the tidying card")
    func showsTheExample() async throws {
        let example = languages().example
        let spoken = Transcription(text: SettingsPresenter.exampleSpoken)
        let transformed = try await RuleBasedTransformer().transform(.init(transcription: spoken)).text
        #expect(example?.groupID == "tidying")
        #expect(example?.spoken == "um so i think we should uh ship it on friday")
        #expect(example?.writtenLabel == "Uttrflow writes · Standard")
        #expect(example?.written == "So I think we should ship it on Friday.")
        #expect(example?.written == transformed)
        #expect(
            SettingsTidyingLevel.rowExplanation
                == "Both levels remove filler sounds and stammers and add punctuation. Standard also repairs grammar slips with an on-device model, which adds a moment to each dictation. Neither level changes, reorders or drops the words you meant."
        )
    }

    /// The tidier removes and formats and never composes, so the copy may not promise a rewrite.
    @Test("promises no rewrite in the tidying copy or example")
    func promisesNoRewrite() {
        let claims = ["rewrite", "word choice", "polish", "improve your", "rephrase"]
        let copy = SettingsTidyingLevel.rowExplanation.lowercased()
        #expect(claims.allSatisfy { !copy.contains($0) })
        let light = SettingsPresenter.tidyExample(.light)
        #expect(light.writtenLabel == "Uttrflow writes · Light")
        #expect(light.written == SettingsPresenter.tidyExample(.standard).written)
    }

    @Test("keeps each language's own name in its offer")
    func namesLanguagesInThemselves() {
        #expect(SettingsLanguage.offered.first { $0.code == .hindi }?.endonym == "हिन्दी")
        for language in SettingsLanguage.offered {
            #expect(language.id == language.code.value)
        }
    }

    /// The recogniser detects only transcribed languages, so an offered one outside them could never be heard.
    @Test("offers only languages the recogniser is allowed to detect")
    func offersOnlyTranscribedLanguages() {
        #expect(SettingsLanguage.offered.map(\.code) == LanguageCode.transcribed)
    }

    @Test("shows the tidying level read out of the stored preference")
    func showsTheTidyingLevel() {
        var settings = Settings.default
        settings.engines.transformerPreference = [.rules]
        guard case .segmented(_, let selected)? = languages(settings).row("tidyingLevel")?.control
        else {
            Issue.record("the tidying row is not a segmented control")
            return
        }
        #expect(selected == SettingsTidyingLevel.light.rawValue)
    }

    @Test("never offers a level that would leave the pipeline with nothing to run")
    func offersNoOffSwitch() {
        guard case .segmented(let options, _)? = languages().row("tidyingLevel")?.control else {
            Issue.record("the tidying row is not a segmented control")
            return
        }
        #expect(options.count == SettingsTidyingLevel.allCases.count)
        for option in options {
            guard case .tidying(let level) = option.change else {
                Issue.record("\(option.id) does not change the tidying level")
                continue
            }
            #expect(level.preference.last == SettingsEngines.floor)
        }
    }

    @Test("explains what still works when this Mac cannot use Standard tidying")
    func explainsAMissingTidyingEngine() {
        var capabilities = SettingsCapabilities.everything
        capabilities.readyTransformers = [SettingsEngines.floor]
        let pane = SettingsPresenter.pane(
            for: .languages, settings: .default, capabilities: capabilities)
        let row = pane.row("tidyingLevel")
        #expect(row?.isEnabled == false)
        #expect(
            row?.unavailability
                == "Full tidying is not available on this Mac yet, so Uttrflow will still apply its rules.")
    }

    @Test("shows the Apple Intelligence cause and offers Settings only when switched off")
    func explainsAppleIntelligenceAvailability() {
        func pane(_ reason: TransformerUnavailableReason) -> SettingsPane {
            var capabilities = SettingsCapabilities.everything
            capabilities.readyTransformers = [.rules]
            capabilities.foundationModelAvailability = .unavailable(reason: reason)
            return SettingsPresenter.pane(
                for: .languages, settings: .default, capabilities: capabilities)
        }

        let switchedOff = pane(.appleIntelligenceDisabled)
        let offRow = switchedOff.row("foundationModelAvailability")
        #expect(offRow?.label == "Apple Intelligence is switched off")
        #expect(offRow?.explanation?.contains("System Settings") == true)
        #expect(
            offRow?.control
                == .action(
                    title: "Open System Settings", change: .openSystemSettings(.appleIntelligence)))

        let downloading = pane(.modelNotReady).row("foundationModelAvailability")
        #expect(downloading?.label == "Apple Intelligence model is downloading")
        #expect(downloading?.control == .status("Downloading"))

        let ineligible = pane(.deviceNotEligible).row("foundationModelAvailability")
        #expect(ineligible?.label == "This Mac cannot run Apple Intelligence")
        #expect(ineligible?.control == .status("Unavailable"))
    }

    @Test("explains what mixing languages does")
    func carriesTheMixedLanguageNote() {
        #expect(languages().callout?.message.contains("Hindi") == true)
    }
}

// MARK: - Dictation

@Suite("Suggestion model failures in Settings")
struct SettingsSuggestionModelFailureTests {
    private func pane(for readiness: SuggestionModelReadiness) -> SettingsPane {
        var settings = Settings.default
        settings.suggestions.isEnabled = true
        var capabilities = SettingsCapabilities.everything
        capabilities.suggestionModel = readiness
        return SettingsPresenter.pane(for: .suggestions, settings: settings, capabilities: capabilities)
    }

    @Test("names a failed fetch and offers connection advice")
    func fetchFailure() {
        let pane = pane(for: .fetchFailed)
        #expect(pane.banner?.title == "The model could not be fetched")
        #expect(pane.banner?.message.contains("Check your connection") == true)
        #expect(pane.row("retrySuggestionModel")?.label == "Suggestion model could not be fetched")
        #expect(pane.row("retrySuggestionModel")?.explanation?.contains("connection") == true)
    }

    @Test("names the required free space and offers the right recovery")
    func insufficientSpace() throws {
        let readiness = SuggestionModelReadiness.insufficientSpace(neededBytes: 3_230_000_000)
        let pane = pane(for: readiness)
        let requiredSpace = try #require(readiness.requiredSpaceDescription)

        #expect(requiredSpace.contains("3"))
        #expect(requiredSpace.contains("GB"))
        #expect(pane.banner?.title == "Not enough disk space")
        #expect(
            pane.banner?.message
                == "This Mac needs \(requiredSpace) free to download AI suggestions. Free some up, then retry."
        )
        #expect(pane.row("retrySuggestionModel")?.label == "Suggestion model needs disk space")
        #expect(pane.row("retrySuggestionModel")?.explanation?.contains(requiredSpace) == true)
        #expect(pane.row("retrySuggestionModel")?.explanation?.contains("connection") == false)
    }

    @Test("names a failed disk load without connection advice")
    func diskLoadFailure() {
        let pane = pane(for: .loadFailed)
        #expect(pane.banner?.title == "The model could not be loaded")
        #expect(pane.banner?.message.contains("loading it again") == true)
        #expect(pane.banner?.message.contains("connection") == false)
        #expect(pane.row("retrySuggestionModel")?.label == "Suggestion model could not be loaded")
        #expect(pane.row("retrySuggestionModel")?.explanation == "Try loading the model again.")
    }
}

@Suite("The Dictation tab")
struct SettingsDictationPaneTests {
    private func dictation(
        _ settings: Settings = .default, _ capabilities: SettingsCapabilities = .everything
    ) -> SettingsPane {
        SettingsPresenter.pane(for: .dictation, settings: settings, capabilities: capabilities)
    }

    @Test("offers no choice of recogniser, since there is one")
    func offersNoRecogniserChoice() {
        #expect(dictation().row("quality") == nil)
        #expect(dictation().groups.allSatisfy { $0.id != "recognition" })
    }

    @Test("says dictation needs no connection")
    func carriesTheOfflineNote() {
        #expect(dictation().callout?.message.contains("internet") == true)
    }

    @Test("offers the one switch that stops learning in every application, reading the stored choice")
    func offersTheLearningSwitch() throws {
        let field = SettingsToggleField.learnsFromDictation
        #expect(dictation().row(field.rawValue)?.control == .toggle(field: field, isOn: true))
        var off = Settings.default
        off.learnsFromDictation = false
        #expect(dictation(off).row(field.rawValue)?.control == .toggle(field: field, isOn: false))
        let updated = try SettingsEditor.apply(
            .toggle(field, isOn: false), to: .default, given: .everything)
        #expect(!updated.learnsFromDictation)
    }

    @Test("opens Corrections, the one page with neither a sidebar row nor a tab here")
    func opensThePagesWithoutASidebarRow() {
        let row = dictation().row("page.corrections")
        #expect(row?.label == SidebarPresenter.title(for: .corrections))
        #expect(row?.control == .action(title: "Open", change: .openPage(.corrections)))
        #expect(row?.isEnabled == true)
        #expect(dictation().row("page.style") == nil && dictation().row("page.diagnostics") == nil)
        #expect(SettingsChange.openPage(.corrections).isRequestToAct)
    }
}

// MARK: - Privacy

@Suite("The Privacy tab")
struct SettingsPrivacyPaneTests {
    private func privacy(_ settings: Settings = .default) -> SettingsPane {
        SettingsPresenter.pane(for: .privacy, settings: settings, capabilities: .everything)
    }

    @Test("counts what left this Mac by purpose, and dictation as none, from the ledger")
    func countsNetworkActivity() {
        let personalisation = SettingsPersonalisation(
            learnedWords: 0, addedWords: 0, transcripts: 0,
            network: [.modelDownload: NetworkTally(count: 3, last: Date())])
        let pane = SettingsPresenter.pane(
            for: .privacy, settings: .default, capabilities: .everything, personalisation: personalisation)
        let network = pane.groups.first { $0.id == "network" }
        #expect(network?.rows.first?.label == "Dictation")
        #expect(network?.rows.first?.control == .status("0 requests"))
        #expect(pane.row("network.modelDownload")?.control == .status("3 requests"))
        #expect(pane.row("network.updateCheck")?.control == .status("0 requests"))
        #expect(network?.rows.count == NetworkPurpose.allCases.count + 1)
        #expect(pane.row("onDevice") == nil)
    }

    @Test("lists what each store keeps under the retention row, hiding the app's own key and lock")
    func listsLocalStorage() {
        let storage = LocalStoreEntry.allCases.map {
            LocalStoreUsage(entry: $0, files: 1, bytes: $0 == .recordings ? 2_000_000 : 0, oldest: nil)
        }
        let personalisation = SettingsPersonalisation(
            learnedWords: 0, addedWords: 0, transcripts: 0, storage: storage)
        let pane = SettingsPresenter.pane(
            for: .privacy, settings: .default, capabilities: .everything, personalisation: personalisation)
        let rows = pane.groups.first { $0.id == "retention" }?.rows.map(\.id) ?? []
        #expect(rows.prefix(2) == ["transcripts", "storage.dictationHistory"])
        let size = { (bytes: Int64) in SettingsControl.status(bytes.formatted(.byteCount(style: .file))) }
        #expect(pane.row("storage.recordings")?.control == size(2_000_000))
        #expect(pane.row("storage.snippets")?.control == size(0))
        #expect(pane.row("storage.encryptionKey") == nil)
        #expect(pane.row("storage.instanceLock") == nil)
        #expect(pane.row("storage.legacyMigrationMarker") == nil)
        #expect(rows.count(where: { $0.hasPrefix("storage.") }) == LocalStoreEntry.allCases.count - 3)
    }

    @Test("renders every purpose at zero on a Mac that has made no request")
    func rendersForZeroActivity() {
        let rows = privacy().groups.first { $0.id == "network" }?.rows ?? []
        #expect(rows.allSatisfy { $0.control == .status("0 requests") })
        #expect(privacy().callout?.message.contains(SettingsPresenter.privacyPromise) == true)
        // A banner is only ever the suggestion model's news, which the capable Mac here has none of.
        #expect(everyPane().allSatisfy { $0.banner == nil })
    }

    @Test("offers only periods the store will keep, and selects the stored one")
    func offersOnlySurvivablePeriods() {
        var settings = Settings.default
        settings.transcriptRetentionDays = 1

        guard case .menu(let options, let selected)? = privacy(settings).row("transcripts")?.control
        else {
            Issue.record("the transcript period is not a pop-up")
            return
        }
        #expect(options.map(\.id) == SettingsRetention.offeredDays.map(String.init))
        #expect(selected == "1")
        #expect(options.allSatisfy { $0.change != .retention(days: 0) })
    }

    /// One period, because the transcript is the one thing kept.
    @Test("offers a period for the text and for nothing else")
    func onlyTranscriptsHaveAPeriod() {
        let periods = privacy().everyRow.filter {
            if case .menu = $0.control { return true }
            return false
        }
        #expect(periods.map(\.id) == ["transcripts"])
    }

    @Test("offers the usage statistics switch, off by default, saying what is sent")
    func offersTheUsageStatisticsSwitch() throws {
        let row = try #require(privacy().row(SettingsToggleField.sharesUsageStatistics.rawValue))
        #expect(row.control == .toggle(field: .sharesUsageStatistics, isOn: false))
        #expect(row.isEnabled)
        #expect(row.label == "Share usage statistics")
        #expect(row.explanation?.contains("linked to your account") == true)
        #expect(row.explanation?.contains("Never what you dictate") == true)

        let updated = try SettingsEditor.apply(.toggle(.sharesUsageStatistics, isOn: true), to: .default)
        #expect(updated.sharesUsageStatistics)
    }

    @Test("every row on this tab can be operated, but forgetting before anything was learned")
    func privacyRowsAreAlwaysOperable() {
        #expect(privacy().everyRow.filter { $0.id != "forgetLearned" }.allSatisfy { $0.isEnabled })
    }

    @Test("offers crash reports off by default, and shows the stored choice")
    func crashReportsAreOptIn() {
        #expect(
            privacy().row("sendsCrashReports")?.control == .toggle(field: .sendsCrashReports, isOn: false))
        var settings = Settings.default
        settings.sendsCrashReports = true
        #expect(
            privacy(settings).row("sendsCrashReports")?.control
                == .toggle(field: .sendsCrashReports, isOn: true))
    }

    @Test("the crash report switch is written through both ways")
    func crashReportSwitchApplies() throws {
        let on = try SettingsEditor.apply(.toggle(.sendsCrashReports, isOn: true), to: .default)
        #expect(on.sendsCrashReports)
        let off = try SettingsEditor.apply(.toggle(.sendsCrashReports, isOn: false), to: on)
        #expect(!off.sendsCrashReports)
    }

    @Test("offers what dictation reads, text near the cursor by default, and writes a choice through")
    func offersTheContextLevel() throws {
        let row = try #require(privacy().row("contextLevel"))
        guard case .segmented(let options, let selectedID) = row.control else {
            Issue.record("the context level is a segmented choice")
            return
        }
        #expect(selectedID == ContextLevel.nearCaret.rawValue)
        #expect(options.map(\.title) == ["App name only", "Text near the cursor"])
        #expect(row.explanation?.contains("text around your cursor") == true)

        let identity = try SettingsEditor.apply(.contextLevel(.identity), to: .default)
        #expect(identity.contextLevel == .identity)
        let identityRow = try #require(privacy(identity).row("contextLevel"))
        #expect(identityRow.explanation?.contains("falls back to its defaults") == true)
        let back = try SettingsEditor.apply(.contextLevel(.nearCaret), to: identity)
        #expect(back.contextLevel == .nearCaret)
    }
}

// MARK: - Rows

@Suite("A row")
struct SettingsRowTests {
    @Test("is operable exactly when it has no reason not to be")
    func enablementFollowsTheReason() {
        let control = SettingsControl.toggle(field: .opensAtLogin, isOn: true)
        #expect(SettingsRow(id: "a", label: "A", control: control).isEnabled)
        #expect(!SettingsRow(id: "a", label: "A", control: control, unavailability: "no").isEnabled)
    }

    @Test("reads out its reason as well as its label, so the reason is never only a colour")
    func voiceOverHearsTheReason() {
        let row = SettingsRow(
            id: "a", label: "Open at login", explanation: "Why",
            control: .toggle(field: .opensAtLogin, isOn: false),
            unavailability: "Not installed as an app.")
        #expect(row.accessibilityLabel == "Open at login. Why. Not installed as an app.")
        #expect(
            SettingsRow(id: "a", label: "Open at login", control: row.control)
                .accessibilityLabel == "Open at login")
        let betaRow = SettingsRow(
            id: "clipboard", label: "Clipboard",
            control: .toggle(field: .clipboardEnabled, isOn: true), badge: BetaFeature.label)
        #expect(betaRow.accessibilityLabel == "Clipboard, beta")
    }

    @Test("reads one full stop between parts, even where a part already ends in one")
    func voiceOverHearsNoDoubledStop() {
        let row = SettingsRow(
            id: "a", label: "Install updates automatically",
            explanation: "Either way it never installs mid-dictation.",
            control: .toggle(field: .installsUpdatesAutomatically, isOn: false),
            unavailability: "This build has no update feed, so there is nothing to check.")
        #expect(!row.accessibilityLabel.contains(".."))
        #expect(
            row.accessibilityLabel
                == "Install updates automatically. Either way it never installs mid-dictation. "
                + "This build has no update feed, so there is nothing to check.")
    }
}

/// Light, dark, or whatever the Mac is set to.
@Suite("Choosing how Uttrflow is drawn")
struct SettingsAppearanceTests {
    /// Dark by default, because the artboards are dark and the ring needs a dark ground.
    @Test("a new install is drawn dark, not however the Mac happens to be set")
    func darkByDefault() {
        #expect(Settings.default.appearance == .dark)
    }

    /// The explanation names the default, so this pins the copy to the decision it describes.
    @Test("the explanation names the appearance a new install actually gets")
    func explanationMatchesTheDefault() {
        let row = SettingsPresenter.appearanceRow(Settings.default)
        let explanation = row.explanation ?? ""

        #expect(Settings.default.appearance == .dark)
        #expect(explanation.contains("drawn \(Settings.default.appearance.title.lowercased())"))
    }

    @Test("all three are offered side by side, and the current one is shown as chosen")
    func offersAllThree() throws {
        let row = SettingsPresenter.appearanceRow(Settings(appearance: .dark))
        guard case .segmented(let options, let selected) = row.control else {
            Issue.record("appearance should be segmented")
            return
        }
        #expect(options.map(\.title) == ["System", "Light", "Dark"])
        #expect(selected == "dark")
    }

    /// The choice stays on offer, for somebody who wants their whole Mac to change together.
    @Test("following the Mac is still on offer")
    func systemIsStillOffered() {
        let row = SettingsPresenter.appearanceRow(Settings())
        guard case .segmented(let options, _) = row.control else {
            Issue.record("appearance should be segmented")
            return
        }
        #expect(options.contains { $0.change == .appearance(.system) })
    }

    @Test("choosing one is applied, and nothing else moves")
    func applying() throws {
        let before = Settings()
        let after = try SettingsEditor.apply(.appearance(.dark), to: before)
        #expect(after.appearance == .dark)
        #expect(
            Settings(appearance: .light, transcriptRetentionDays: after.transcriptRetentionDays)
                .transcriptRetentionDays == before.transcriptRetentionDays)
        #expect(after.hotkey == before.hotkey)
        #expect(after.opensAtLogin == before.opensAtLogin)
    }

    /// Every Mac can draw itself light or dark, so there is no capability to refuse it on.
    @Test("it is never refused for want of a capability")
    func neverRefused() throws {
        for appearance in AppAppearance.allCases {
            let after = try SettingsEditor.apply(
                .appearance(appearance), to: Settings(),
                given: SettingsCapabilities(
                    launchAtLogin: .unavailable, canPlayRecordingSound: false,
                    readyTransformers: []))
            #expect(after.appearance == appearance)
        }
    }

    /// A preferences file with no appearance key keeps every other choice and takes the default.
    @Test("a settings blob written before this existed still decodes")
    func decodesWithoutTheKey() throws {
        let json = """
            {"opensAtLogin":false,"transcriptRetentionDays":30}
            """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(decoded.appearance == .dark)
        #expect(decoded.opensAtLogin == false)
        #expect(decoded.transcriptRetentionDays == 30)
    }
}

/// The Updates group: which build this is, a way to ask now, and whether to be asked.
@Suite("Updates on the General tab")
struct SettingsUpdatesTests {
    private static func general(
        _ capabilities: SettingsCapabilities, _ settings: Settings = .default
    ) -> SettingsGroup? {
        SettingsPresenter.pane(for: .general, settings: settings, capabilities: capabilities)
            .groups.first { $0.id == "updates" }
    }

    @Test("shows the version, a way to check, and both automatic preferences")
    func theWholeGroup() throws {
        let group = try #require(Self.general(.everything))
        #expect(group.title == "Updates")
        #expect(
            group.rows.map(\.id) == [
                "version", "checkForUpdates", "checksForUpdatesAutomatically",
                "installsUpdatesAutomatically",
            ])

        let version = try #require(group.rows.first { $0.id == "version" })
        #expect(version.control == .text("1.0.0 (1)"))
        #expect(version.unavailability == nil)
    }

    @Test("Check Now remains available with automatic checks off")
    func checkingIsAnAction() throws {
        var settings = Settings.default
        settings.checksForUpdatesAutomatically = false
        let row = try #require(
            Self.general(.everything, settings)?.rows.first { $0.id == "checkForUpdates" })
        #expect(row.control == .action(title: "Check Now", change: .checkForUpdatesNow))
        #expect(row.unavailability == nil)
    }

    /// The group stays in a build that cannot update, showing the version and why the rest is inert.
    @Test("a build with no feed keeps the version and explains the rest")
    func noFeed() throws {
        var capabilities = SettingsCapabilities.everything
        capabilities.canCheckForUpdates = false

        let group = try #require(Self.general(capabilities))
        #expect(group.rows.contains { $0.id == "version" })

        for id in ["checkForUpdates", "checksForUpdatesAutomatically", "installsUpdatesAutomatically"] {
            let row = try #require(group.rows.first { $0.id == id })
            #expect(row.unavailability != nil, "\(id) should say why it cannot act")
        }
    }

    @Test("a build that cannot name its version omits that row rather than inventing one")
    func noVersion() throws {
        var capabilities = SettingsCapabilities.everything
        capabilities.versionDescription = nil

        let group = try #require(Self.general(capabilities))
        #expect(!group.rows.contains { $0.id == "version" })
        // The rest is unaffected: not knowing the version says nothing about updating.
        #expect(group.rows.first { $0.id == "checkForUpdates" }?.unavailability == nil)
    }

    @Test("the switch reads the setting rather than a default")
    func switchFollowsTheSetting() throws {
        for isOn in [true, false] {
            var settings = Settings.default
            settings.installsUpdatesAutomatically = isOn
            let group = try #require(Self.general(.everything, settings))
            let row = try #require(group.rows.first { $0.id == "installsUpdatesAutomatically" })
            #expect(row.control == .toggle(field: .installsUpdatesAutomatically, isOn: isOn))
        }
    }

    @Test("the automatic-check switch reads the saved setting")
    func automaticCheckSwitchFollowsSetting() throws {
        for isOn in [true, false] {
            var settings = Settings.default
            settings.checksForUpdatesAutomatically = isOn
            let group = try #require(Self.general(.everything, settings))
            let row = try #require(group.rows.first { $0.id == "checksForUpdatesAutomatically" })
            #expect(row.control == .toggle(field: .checksForUpdatesAutomatically, isOn: isOn))
        }
    }
}

/// Applying the two update changes.
@Suite("Updating, applied")
struct SettingsUpdateEditingTests {
    @Test("the automatic-check switch is written through")
    func togglesAutomaticChecksThrough() throws {
        var settings = Settings.default
        settings.checksForUpdatesAutomatically = true
        let updated = try SettingsEditor.apply(
            .toggle(.checksForUpdatesAutomatically, isOn: false), to: settings)
        #expect(!updated.checksForUpdatesAutomatically)
    }

    @Test("the switch is written through")
    func togglesThrough() throws {
        var settings = Settings.default
        settings.installsUpdatesAutomatically = true
        let updated = try SettingsEditor.apply(
            .toggle(.installsUpdatesAutomatically, isOn: false), to: settings)
        #expect(updated.installsUpdatesAutomatically == false)
    }

    @Test("a build with no feed refuses the switch and says why")
    func refusedWithoutAFeed() {
        var capabilities = SettingsCapabilities.everything
        capabilities.canCheckForUpdates = false
        let reason = SettingsEditor.unavailability(
            of: .installsUpdatesAutomatically, given: capabilities, in: .default)
        #expect(reason?.contains("no update feed") == true)
    }

    /// It travels in the change enum and alters nothing, which is what this asserts.
    @Test("asking for a check changes no setting at all")
    func checkingChangesNothing() throws {
        let settings = Settings.default
        let updated = try SettingsEditor.apply(.checkForUpdatesNow, to: settings)
        #expect(updated == settings)
    }

    /// Which is why it has to be routed rather than saved; see `SettingsViewModel.apply`.
    @Test("and says so, so a screen can hand it on instead of storing it")
    func checkingIsARequestToAct() {
        #expect(SettingsChange.checkForUpdatesNow.isRequestToAct)
        #expect(SettingsChange.chooseApplicationToTurnOffSuggestions.isRequestToAct)
        #expect(!SettingsChange.toggle(.opensAtLogin, isOn: true).isRequestToAct)
        #expect(!SettingsChange.retention(days: 7).isRequestToAct)
        #expect(!SettingsChange.pauseSuggestions(isOn: true).isRequestToAct)
        #expect(SettingsChange.manageClipboardExclusions.isRequestToAct)
        #expect(SettingsChange.pauseClipboardCapture(isOn: true).isRequestToAct)
    }
}

@Suite("A shortcut the app could not claim")
struct UnarmedShortcutTests {
    private func row(_ capabilities: SettingsCapabilities) -> SettingsRow? {
        SettingsPresenter.pane(for: .general, settings: .default, capabilities: capabilities)
            .groups.flatMap(\.rows).first { $0.id == "shortcut.clipboard" }
    }

    /// #142: the row showed ⇧⌘V as though it worked while the key fell through and pasted.
    @Test("says so, instead of showing a key that does nothing")
    func saysSo() throws {
        var capabilities = SettingsCapabilities.everything
        capabilities.unarmedShortcuts = [.clipboard: .shortcutUnavailable]
        let shown = try #require(row(capabilities))
        #expect(shown.explanation == SettingsPresenter.unarmed(.shortcutUnavailable))
    }

    @Test("keeps the unarmed explanation ahead of the activation mode")
    func unarmedDictateIsStillExplainedFirst() throws {
        var settings = Settings.default
        settings.hotkeyActivation = .pressToToggle
        var capabilities = SettingsCapabilities.everything
        capabilities.unarmedShortcuts = [.dictate: .shortcutUnavailable]

        let shown = try #require(
            SettingsPresenter.pane(for: .general, settings: settings, capabilities: capabilities)
                .groups.flatMap(\.rows).first { $0.id == "shortcut.dictate" })
        #expect(shown.explanation == SettingsPresenter.unarmed(.shortcutUnavailable))
    }

    @Test(
        "names the refusal, so each cause reads differently",
        arguments: [HotkeyError.observationNotPermitted, .accessibilityNeedsRefresh, .shortcutUnavailable])
    func namesTheCause(_ cause: HotkeyError) throws {
        var capabilities = SettingsCapabilities.everything
        capabilities.unarmedShortcuts = [.clipboard: cause]
        let shown = try #require(row(capabilities))
        #expect(shown.explanation?.hasPrefix("Unavailable") == true)
        #expect(shown.explanation?.hasSuffix(cause.userMessage) == true)
    }

    @Test("and every other row is left alone")
    func othersAreUntouched() throws {
        var capabilities = SettingsCapabilities.everything
        capabilities.unarmedShortcuts = [.dictate: .shortcutUnavailable]
        let shown = try #require(row(capabilities))
        #expect(shown.explanation != SettingsPresenter.unarmed(.shortcutUnavailable))
    }

    @Test("while an armed one keeps the explanation it always had")
    func armedIsUnchanged() throws {
        let shown = try #require(row(.everything))
        #expect(shown.explanation != SettingsPresenter.unarmed(.shortcutUnavailable))
    }
}

@Suite("A shortcut returned to its default")
struct ReturnedShortcutTests {
    private func row(_ id: String, in settings: Settings) -> SettingsRow? {
        SettingsPresenter.pane(for: .general, settings: settings, capabilities: .everything)
            .groups.flatMap(\.rows).first { $0.id == id }
    }

    /// Issue 342: a held ⌘ that quietly became ⌥Space would look like the app forgot the user's choice.
    @Test("says why, on the row whose shortcut was put back")
    func saysWhy() throws {
        var settings = Settings.default
        settings.shortcutsReturnedToDefault = [.dictate]
        settings.hotkeyActivation = .pressToToggle

        let shown = try #require(row("shortcut.dictate", in: settings))

        #expect(shown.explanation == SettingsPresenter.returnedToDefault)
        let untouched = try #require(row("shortcut.clipboard", in: settings))
        #expect(untouched.explanation != SettingsPresenter.returnedToDefault)
    }

    @Test("says nothing of it once the note is gone")
    func saysNothingWithoutTheNote() throws {
        let shown = try #require(row("shortcut.dictate", in: .default))

        #expect(shown.explanation != SettingsPresenter.returnedToDefault)
    }
}
