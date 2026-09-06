import UttrflowCore
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    static func style(
        settings: Settings = .default, capabilities: SettingsCapabilities = .everything
    ) -> StylePagePresentation {
        StylePagePresenter.page(
            for: StylePageSnapshot(settings: settings, capabilities: capabilities))
    }
}

@Suite("Style: how much Uttrflow tidies")
struct StyleTidyingTests {
    /// The `Settings-Dictation` artboard offers Off/Light/Standard and this page offers
    /// Light/Standard. Two is right, in code as well as on the screen: the transformer
    /// preference always ends in a floor that can handle anything, so something always
    /// runs and an "Off" the pipeline cannot be in would be a control that changes
    /// nothing. This test is what stops a third option being added back.
    @Test("there are exactly two levels of tidying, and no off")
    func twoLevels() {
        let group = HistoryFixture.style().groups[0].group
        guard case .segmented(let options, _) = group.rows[0].control else {
            Issue.record("the tidying row must be a segmented control")
            return
        }
        #expect(options.map(\.title) == ["Light", "Standard"])
        #expect(!options.contains { $0.title.lowercased() == "off" })
    }

    @Test("the level shown is the one the stored preference means")
    func readsTheSetting() {
        var settings = Settings.default
        settings.engines.transformerPreference = SettingsTidyingLevel.light.preference
        guard
            case .segmented(_, let selected) = HistoryFixture.style(settings: settings)
                .groups[0].group.rows[0].control
        else {
            Issue.record("the tidying row must be a segmented control")
            return
        }
        #expect(selected == "light")
    }

    /// The same ``SettingsChange`` the settings window reports, so ``SettingsEditor``
    /// stays the only thing that decides whether a change may happen.
    @Test("choosing a level reports the settings window's own change")
    func reportsASettingsChange() {
        guard
            case .segmented(let options, _) = HistoryFixture.style().groups[0].group.rows[0]
                .control
        else {
            Issue.record("the tidying row must be a segmented control")
            return
        }
        #expect(options.map(\.change) == [.tidying(.light), .tidying(.standard)])
    }

    /// A control the user can move that changes nothing teaches them the app is broken.
    @Test("a Mac that cannot tidy beyond the floor says so on the row")
    func unavailable() {
        let capabilities = SettingsCapabilities(
            launchAtLogin: .enabled, canPlayRecordingSound: true, readySpeechEngines: [],
            readyTransformers: [])
        let row = HistoryFixture.style(capabilities: capabilities).groups[0].group.rows[0]
        #expect(!row.isEnabled)
        #expect(row.unavailability?.contains("punctuate only") == true)
    }
}

@Suite("The worked example")
struct StyleExampleTests {
    /// The only honest way to explain a setting whose effect is a matter of taste.
    @Test("the same sentence is shown at every level")
    func bothWays() {
        let example = HistoryFixture.style().example
        #expect(example.heading == "The same sentence, both ways")
        #expect(example.spokenLabel == "You said")
        #expect(example.spoken == "um so i think we should uh ship it on friday")
        #expect(example.outcomes.map(\.level) == SettingsTidyingLevel.allCases)
        #expect(example.outcomes.map(\.id) == ["light", "standard"])
    }

    @Test("only the outcome the user is currently on is marked")
    func currentIsMarked() {
        let example = HistoryFixture.style().example
        #expect(example.outcomes.filter(\.isCurrent).map(\.level) == [.standard])
    }

    @Test("light keeps the filler and standard drops it")
    func showsTheDifference() {
        #expect(StylePagePresenter.tidied(at: .light).contains("uh"))
        #expect(!StylePagePresenter.tidied(at: .standard).contains("uh"))
    }

    /// The example belongs under the card it explains, and nowhere else.
    @Test("the example follows the tidying card alone")
    func placement() {
        let groups = HistoryFixture.style().groups
        #expect(groups.map(\.isFollowedByExample) == [true, false])
        #expect(groups.map(\.id) == ["tidying", "languages"])
    }
}

@Suite("Style: which languages Uttrflow listens for")
struct StyleLanguageTests {
    @Test("every language Uttrflow transcribes is offered")
    func offered() {
        let rows = HistoryFixture.style().groups[1].group.rows
        #expect(rows.map(\.label) == SettingsLanguage.offered.map(\.name))
        #expect(HistoryFixture.style().groups[1].group.title == "Languages")
    }

    @Test("a language the user speaks is ticked")
    func ticked() {
        let rows = HistoryFixture.style().groups[1].group.rows
        guard case .tick(let isTicked, let change) = rows[0].control else {
            Issue.record("a language row must be a tick")
            return
        }
        #expect(isTicked)
        #expect(change == .spokenLanguage(.english, isSpoken: false))
    }

    /// Said on the row before it is tried, rather than refused afterwards.
    @Test("the last language cannot be unticked, and the row says why")
    func theLastOne() {
        let rows = HistoryFixture.style().groups[1].group.rows
        #expect(rows[0].unavailability == "Uttrflow needs at least one language to listen for.")
        #expect(rows[1].unavailability == nil)
    }

    @Test("a second language frees the first")
    func twoLanguages() {
        var settings = Settings.default
        settings.profile.preferredLanguages = [.english, .hindi]
        let rows = HistoryFixture.style(settings: settings).groups[1].group.rows
        #expect(rows.compactMap(\.unavailability).isEmpty)
    }
}

@Suite("The rest of the Style page")
struct StylePageChromeTests {
    @Test("the page has no toolbar of its own")
    func chrome() {
        let chrome = HistoryFixture.style().chrome
        #expect(chrome.title == "Style")
        #expect(chrome.search == nil)
        #expect(chrome.scope == nil)
        #expect(chrome.addAction == nil)
    }

    @Test("the callout says where tidying is strongest and where it is not")
    func callout() {
        let callout = HistoryFixture.style().callout
        #expect(callout.symbolName == "globe")
        #expect(callout.message.contains("strongest in English"))
        #expect(callout.message.contains("Corrections"))
    }

    /// ``SettingsControl`` is a closed set and this page can draw two of it.
    /// `StyleControlView` draws nothing for the rest, so a third arriving here must be a
    /// failing test rather than a row that silently disappears.
    @Test("the page asks only for the two controls its view can draw")
    func onlyDrawableControls() {
        for group in HistoryFixture.style().groups {
            for row in group.group.rows {
                switch row.control {
                case .segmented, .tick:
                    continue
                case .toggle, .menu, .anchorPicker, .shortcut, .removal, .action, .text,
                    .applicationSwitch:
                    Issue.record("the Style page asked for a control its view cannot draw")
                }
            }
        }
    }
}
