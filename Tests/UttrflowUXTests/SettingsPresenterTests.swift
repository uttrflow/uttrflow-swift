import Foundation
import UttrflowCore
import UttrflowSettings
import Testing

@testable import UttrflowUX

// MARK: - Fixtures

/// Every pane a fully capable Mac would draw, in every state the counts can be in.
///
/// The counts are swept as well as the tabs, because a destructive row reads differently
/// for each of them and a sentence written for one shape would otherwise never be looked
/// at in the others.
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
            case .shortcut(let keys):
                strings += keys
            case .removal(let removal):
                strings += [removal.title]
                strings += [
                    removal.confirmation?.title, removal.confirmation?.message,
                    removal.confirmation?.confirmTitle, removal.confirmation?.cancelTitle,
                ].compactMap(\.self)
            case .toggle, .anchorPicker, .tick:
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

    @Test("draws something on every tab")
    func noTabIsEmpty() {
        for pane in everyPane() {
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
                case .toggle, .anchorPicker, .shortcut, .tick, .removal:
                    break
                }
            }
        }
    }

    /// §16, on this screen as much as on the floating button: the user chooses how much
    /// help they want, never which implementation gives it to them.
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

// MARK: - General

@Suite("The General tab")
struct SettingsGeneralPaneTests {
    private func general(
        _ settings: Settings = .default, _ capabilities: SettingsCapabilities = .everything
    ) -> SettingsPane {
        SettingsPresenter.pane(for: .general, settings: settings, capabilities: capabilities)
    }

    @Test("shows the shortcut in force on keycaps")
    func showsTheShortcut() {
        var settings = Settings.default
        settings.hotkey = HotkeyBinding(keyCode: 40, modifiers: [.command])
        #expect(general(settings).row("hotkey")?.control == .shortcut(keys: ["⌘", "K"]))
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

    @Test("shows the corner the floating button is parked in")
    func showsTheAnchor() {
        var settings = Settings.default
        settings.floatingButtonAnchor = .bottomLeft
        #expect(general(settings).row("anchor")?.control == .anchorPicker(selected: .bottomLeft))
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

    @Test("ticks the languages the user speaks and leaves the rest to be chosen")
    func ticksWhatIsSpoken() {
        var settings = Settings.default
        settings.profile.preferredLanguages = [.hindi]
        let pane = languages(settings)

        #expect(
            pane.row("hi")?.control
                == .tick(
                    isTicked: true, change: .spokenLanguage(.hindi, isSpoken: false)))
        #expect(
            pane.row("en")?.control
                == .tick(
                    isTicked: false, change: .spokenLanguage(.english, isSpoken: true)))
    }

    @Test("locks the only language the user has, rather than refusing it afterwards")
    func theLastLanguageCannotBeUntangled() {
        #expect(languages().row("en")?.isEnabled == false)
        #expect(languages().row("hi")?.isEnabled == true)

        var both = Settings.default
        both.profile.preferredLanguages = [.english, .hindi]
        #expect(languages(both).row("en")?.isEnabled == true)
    }

    @Test("names each language in itself as well as in English")
    func namesLanguagesInThemselves() {
        #expect(languages().row("hi")?.explanation == "हिन्दी")
        for language in SettingsLanguage.offered {
            #expect(language.id == language.code.value)
        }
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

    @Test("says when this Mac cannot tidy beyond punctuation")
    func explainsAMissingTidyingEngine() {
        var capabilities = SettingsCapabilities.everything
        capabilities.readyTransformers = [SettingsEngines.floor]
        let pane = SettingsPresenter.pane(
            for: .languages, settings: .default, capabilities: capabilities)
        #expect(pane.row("tidyingLevel")?.isEnabled == false)
    }

    @Test("explains what mixing languages does")
    func carriesTheMixedLanguageNote() {
        #expect(languages().callout?.message.contains("Hindi") == true)
    }
}

// MARK: - Dictation

@Suite("The Dictation tab")
struct SettingsDictationPaneTests {
    private func dictation(
        _ settings: Settings = .default, _ capabilities: SettingsCapabilities = .everything
    ) -> SettingsPane {
        SettingsPresenter.pane(for: .dictation, settings: settings, capabilities: capabilities)
    }

    @Test("shows the trade the stored engine represents, not the engine")
    func showsTheQuality() {
        var settings = Settings.default
        settings.engines.speech = .appleSpeech
        guard
            case .segmented(let options, let selected)? = dictation(settings).row("quality")?
                .control
        else {
            Issue.record("the quality row is not a segmented control")
            return
        }
        #expect(selected == SettingsTranscriptionQuality.faster.rawValue)
        #expect(options.count == SettingsTranscriptionQuality.allCases.count)
    }

    @Test("stays operable while either option can still run")
    func operableWhileOneEngineIsReady() {
        var capabilities = SettingsCapabilities.everything
        capabilities.readySpeechEngines = [.appleSpeech]
        #expect(dictation(.default, capabilities).row("quality")?.isEnabled == true)

        capabilities.readySpeechEngines = []
        #expect(dictation(.default, capabilities).row("quality")?.isEnabled == false)
    }

    @Test("says dictation needs no connection")
    func carriesTheOfflineNote() {
        #expect(dictation().callout?.message.contains("internet") == true)
    }
}

// MARK: - Privacy

@Suite("The Privacy tab")
struct SettingsPrivacyPaneTests {
    private func privacy(_ settings: Settings = .default) -> SettingsPane {
        SettingsPresenter.pane(for: .privacy, settings: settings, capabilities: .everything)
    }

    @Test("opens with the promise, before anything that can be changed")
    func opensWithThePromise() {
        let banner = privacy().banner
        #expect(banner?.title.isEmpty == false)
        #expect(banner?.message.isEmpty == false)
        #expect(banner?.symbolName.isEmpty == false)
        // No other tab claims one, so a banner always means this promise.
        #expect(Set(everyPane().filter { $0.banner != nil }.map(\.tab)) == [.privacy])
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

    /// One period, because there is one thing kept. A row offering to keep recordings
    /// for a while would be offering to configure something the app never does.
    @Test("offers a period for the text and for nothing else")
    func onlyTranscriptsHaveAPeriod() {
        let periods = privacy().everyRow.filter {
            if case .menu = $0.control { return true }
            return false
        }
        #expect(periods.map(\.id) == ["transcripts"])
    }

    @Test("every row on this tab can be operated")
    func privacyRowsAreAlwaysOperable() {
        #expect(privacy().everyRow.allSatisfy { $0.isEnabled })
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
    }
}

/// Light, dark, or whatever the Mac is set to.
@Suite("Choosing how Uttrflow is drawn")
struct SettingsAppearanceTests {
    /// The one choice here worth arguing about. Uttrflow's artboards are dark — the ring
    /// on the home page is two saturated colours that only hold their meaning against
    /// something dark — and the app that was designed should be the app that is seen.
    @Test("a new install is drawn dark, not however the Mac happens to be set")
    func darkByDefault() {
        #expect(Settings.default.appearance == .dark)
    }

    /// The explanation names the default, so the two have to agree. They did not: the
    /// row went on saying "drawn light" for a build after the default became dark, and
    /// nothing failed — copy that describes a decision has to be pinned to the decision.
    @Test("the explanation names the appearance a new install actually gets")
    func explanationMatchesTheDefault() {
        let row = SettingsPresenter.appearanceRow(Settings.default)
        let explanation = row.explanation ?? ""

        #expect(Settings.default.appearance == .dark)
        #expect(explanation.contains("drawn \(Settings.default.appearance.title.lowercased())"))
    }

    @Test("all three are offered, and the current one is shown as chosen")
    func offersAllThree() throws {
        let row = SettingsPresenter.appearanceRow(Settings(appearance: .dark))
        guard case .menu(let options, let selected) = row.control else {
            Issue.record("appearance should be a menu")
            return
        }
        #expect(options.map(\.title) == ["Light", "Dark", "Match my Mac"])
        #expect(selected == "dark")
    }

    /// Taking the choice away is worse than defaulting it: somebody who wants their whole
    /// Mac to change together should be able to have that.
    @Test("following the Mac is still on offer")
    func systemIsStillOffered() {
        let row = SettingsPresenter.appearanceRow(Settings())
        guard case .menu(let options, _) = row.control else { return }
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

    /// Drawing itself light or dark is something every Mac can do, so there is no
    /// capability to refuse it on.
    @Test("it is never refused for want of a capability")
    func neverRefused() throws {
        for appearance in AppAppearance.allCases {
            let after = try SettingsEditor.apply(
                .appearance(appearance), to: Settings(),
                given: SettingsCapabilities(
                    launchAtLogin: .unavailable, canPlayRecordingSound: false,
                    readySpeechEngines: [], readyTransformers: []))
            #expect(after.appearance == appearance)
        }
    }

    /// A preferences file from a build that had no appearance key must not lose every
    /// other choice in it, and must land on the default rather than on nothing.
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
