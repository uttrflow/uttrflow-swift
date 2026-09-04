import Foundation
import Synchronization
import Testing
import UttrflowClipboard
import UttrflowDictionary
import UttrflowHistory
import UttrflowPredict
import UttrflowSettings

@testable import UttrflowUX

// MARK: - Fixtures

/// A moment to measure the half-hour pause from, so no test depends on when it ran.
private let noon = Date(timeIntervalSince1970: 1_700_000_000)

private let xcode = "com.apple.dt.xcode"
private let notes = "com.apple.notes"

/// Settings with the feature switched on, which is what most of these are about.
private func switchedOn() -> Settings {
    var settings = Settings.default
    settings.suggestions.isEnabled = true
    return settings
}

private func pane(
    _ settings: Settings,
    personalisation: SettingsPersonalisation = .nothing,
    at moment: Date = noon
) -> SettingsPane {
    SettingsPresenter.pane(
        for: .suggestions, settings: settings, capabilities: .everything,
        personalisation: personalisation, at: moment)
}

private func row(_ id: String, in pane: SettingsPane) -> SettingsRow? {
    pane.groups.flatMap(\.rows).first { $0.id == id }
}

/// A corpus in memory, so a reset can be driven end to end without a database.
private final class InMemoryCorpus: SuggestionCorpus {
    private let counts: Mutex<[String: Int]>

    init(_ initial: [String: Int]) {
        counts = Mutex(initial)
    }

    var contents: [String: Int] { counts.withLock { $0 } }

    func learnedSuggestions() async -> [String: Int] { contents }

    func forgetSuggestions(from bundleIdentifier: String) async throws {
        counts.withLock { $0[bundleIdentifier.lowercased()] = nil }
    }

    func forgetEverySuggestion() async throws {
        counts.withLock { $0 = [:] }
    }
}

// MARK: - The pane

@Suite("The suggestions pane")
struct SettingsSuggestionsPaneTests {
    @Test("is a tab of its own, between Dictation and Privacy")
    func hasItsOwnTab() {
        let tabs = SettingsPresenter.tabs()
        #expect(tabs.map(\.tab) == SettingsTab.allCases)
        #expect(tabs.first { $0.tab == .suggestions }?.title == "Suggestions")
    }

    @Test("offers the master switch off, which is what the feature ships as")
    func theMasterSwitchIsOff() throws {
        let master = try #require(row("suggestionsEnabled", in: pane(.default)))
        #expect(master.control == .toggle(field: .suggestionsEnabled, isOn: false))
        #expect(master.isEnabled)
    }

    @Test("says why quiet mode cannot be chosen while the feature is off")
    func quietDependsOnTheMasterSwitch() throws {
        let off = try #require(row("quietSuggestions", in: pane(.default)))
        #expect(off.unavailability == SettingsEditor.suggestionsAreOff)

        let on = try #require(row("quietSuggestions", in: pane(switchedOn())))
        #expect(on.isEnabled)
    }

    @Test("offers a half-hour pause, and offers to lift it while one is running")
    func thePauseIsOfferedBothWays() throws {
        var settings = switchedOn()
        let ready = try #require(row("pauseSuggestions", in: pane(settings)))
        #expect(
            ready.control == .action(title: "Pause for 30 Minutes", change: .pauseSuggestions(isOn: true)))

        settings.suggestions.setPaused(true, at: noon)
        let running = try #require(
            row("pauseSuggestions", in: pane(settings, at: noon.addingTimeInterval(60))))
        #expect(running.control == .action(title: "Resume", change: .pauseSuggestions(isOn: false)))
        #expect(running.explanation?.contains("29 minutes") == true)
    }

    @Test("offers to pause again once a pause has run itself out")
    func aPauseThatRanOutIsOfferedAgain() throws {
        var settings = switchedOn()
        settings.suggestions.setPaused(true, at: noon)
        let after = try #require(
            row("pauseSuggestions", in: pane(settings, at: noon.addingTimeInterval(3_600))))
        #expect(
            after.control == .action(title: "Pause for 30 Minutes", change: .pauseSuggestions(isOn: true)))
    }

    @Test("never counts a running pause down to nothing")
    func aRunningPauseIsNeverZeroMinutes() {
        #expect(SettingsPresenter.pauseSentence(1).contains("1 minute."))
        #expect(SettingsPresenter.pauseSentence(nil).contains("half an hour"))
    }

    @Test("says why an application is off only when the user did not choose it")
    func explainsOnlyWhatTheUserDidNotChoose() {
        #expect(SettingsPresenter.applicationSentence(.on) == nil)
        #expect(SettingsPresenter.applicationSentence(.turnedOff)?.isEmpty == false)
        #expect(SettingsPresenter.applicationSentence(.offByDefault)?.contains("whole file") == true)
    }
}

// MARK: - The list nothing can hide in

@Suite("Everything switched off is findable")
struct SettingsSuggestionApplicationListTests {
    @Test("lists all four shipped editors, each with a switch beside it")
    func theShippedEditorsAreListed() throws {
        let shown = pane(switchedOn())
        for editor in SuggestionApplications.offByDefault {
            let listed = try #require(row("suggestionsIn.\(editor.bundleIdentifier)", in: shown))
            #expect(listed.label == editor.name)
            #expect(
                listed.control
                    == .applicationSwitch(
                        isOn: false,
                        change: .suggestionsHere(application: editor.bundleIdentifier, isOn: true)))
        }
    }

    @Test("lists an application the moment it is switched off, whichever way that happened")
    func anythingSwitchedOffIsListed() throws {
        var settings = switchedOn()
        settings = try SettingsEditor.apply(
            .suggestionsHere(application: notes, isOn: false), to: settings)
        let listed = try #require(row("suggestionsIn.\(notes)", in: pane(settings)))
        #expect(
            listed.control
                == .applicationSwitch(isOn: false, change: .suggestionsHere(application: notes, isOn: true)))
    }

    @Test("lists an application that was switched off, so switching off cannot hide one")
    func switchingOffCannotHideAnApplication() throws {
        var settings = switchedOn()
        settings.suggestions.set(notes, isOn: false)
        #expect(row("suggestionsIn.\(notes)", in: pane(settings)) != nil)
    }

    @Test("keeps the list reachable when the feature itself is off, saying what to do first")
    func theListIsThereWithTheFeatureOff() throws {
        let listed = try #require(row("suggestionsIn.\(xcode)", in: pane(.default)))
        #expect(listed.unavailability == SettingsEditor.suggestionsAreOff)
    }

    @Test("offers the accept key only for an application suggestions actually run in")
    func theAcceptKeyFollowsTheSwitch() throws {
        var settings = switchedOn()
        #expect(row("suggestionAcceptKey.\(xcode)", in: pane(settings)) == nil)

        settings.suggestions.set(xcode, isOn: true)
        let key = try #require(row("suggestionAcceptKey.\(xcode)", in: pane(settings)))
        #expect(
            key.control
                == .menu(
                    options: AcceptKey.allCases.map {
                        SettingsOption(
                            id: $0.rawValue, title: $0.title,
                            change: .suggestionAcceptKey(application: xcode, key: $0))
                    },
                    selectedID: AcceptKey.optionTab.rawValue))
    }

    @Test("gives every row on the pane an id of its own")
    func rowIdsAreUnique() {
        var settings = switchedOn()
        settings.suggestions.set(xcode, isOn: true)
        settings.suggestions.set(notes, isOn: false)
        let ids = pane(
            settings,
            personalisation: SettingsPersonalisation(
                learnedWords: 0, addedWords: 0, transcripts: 0, suggestions: [xcode: 3])
        ).groups.flatMap(\.rows).map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: - Changing them

@Suite("Changing a suggestion setting")
struct SettingsSuggestionEditorTests {
    @Test("writes the master switch and quiet mode to their own fields")
    func theTwoSwitchesHaveBackings() throws {
        let on = try SettingsEditor.apply(.toggle(.suggestionsEnabled, isOn: true), to: .default)
        #expect(on.suggestions.isEnabled)

        let quiet = try SettingsEditor.apply(.toggle(.quietSuggestions, isOn: true), to: on)
        #expect(quiet.suggestions.isQuiet)
        #expect(quiet.suggestions.isEnabled)
    }

    @Test("refuses every suggestion control while the feature itself is off")
    func refusesWhileTheFeatureIsOff() {
        let changes: [SettingsChange] = [
            .toggle(.quietSuggestions, isOn: true),
            .suggestionsHere(application: notes, isOn: false),
            .suggestionAcceptKey(application: notes, key: .rightArrow),
            .pauseSuggestions(isOn: true),
        ]
        for change in changes {
            #expect(throws: SettingsRejection(reason: SettingsEditor.suggestionsAreOff)) {
                try SettingsEditor.apply(change, to: .default)
            }
        }
    }

    @Test("switches one application without touching any other")
    func oneApplicationAtATime() throws {
        var settings = switchedOn()
        settings = try SettingsEditor.apply(
            .suggestionsHere(application: notes, isOn: false), to: settings)
        #expect(settings.suggestions.state(of: notes) == .turnedOff)
        #expect(settings.suggestions.state(of: "com.apple.Mail") == .on)
    }

    @Test("writes the accept key the user chose for that application alone")
    func writesOneAcceptKey() throws {
        var settings = switchedOn()
        settings = try SettingsEditor.apply(
            .suggestionAcceptKey(application: xcode, key: .tab), to: settings)
        #expect(settings.suggestions.acceptKeys.key(forBundleIdentifier: xcode) == .tab)
        #expect(settings.suggestions.acceptKeys.key(forBundleIdentifier: notes) == .tab)
        #expect(
            settings.suggestions.acceptKeys.key(forBundleIdentifier: "com.apple.Terminal")
                == .rightArrow)
    }

    @Test("starts the pause from the moment it was asked for, and lifts it on request")
    func thePauseIsMeasuredFromTheGivenMoment() throws {
        var settings = try SettingsEditor.apply(
            .pauseSuggestions(isOn: true), to: switchedOn(), at: noon)
        #expect(settings.suggestions.pausedUntil == noon.addingTimeInterval(30 * 60))

        settings = try SettingsEditor.apply(.pauseSuggestions(isOn: false), to: settings, at: noon)
        #expect(settings.suggestions.pausedUntil == nil)
    }

    @Test("names each accept key on screen, and explains only the two that are not Tab")
    func everyAcceptKeyHasWords() {
        for key in AcceptKey.allCases {
            #expect(!key.title.isEmpty)
        }
        #expect(AcceptKey.tab.explanation == nil)
        #expect(AcceptKey.rightArrow.explanation?.isEmpty == false)
        #expect(AcceptKey.optionTab.explanation?.isEmpty == false)
    }
}

// MARK: - The fifth level of forgetting

@Suite("Forgetting what one application taught")
struct SettingsForgetSuggestionsTests {
    private let learned = SettingsPersonalisation(
        learnedWords: 0, addedWords: 0, transcripts: 0, suggestions: [xcode: 214])

    @Test("removes that application's completions and nothing else")
    func namesOneApplicationOnly() {
        let reset = SettingsReset.suggestions(inApplication: xcode)
        #expect(reset.targets == [.suggestions(inApplication: xcode)])
        #expect(!reset.isConfirmed)
    }

    @Test("takes the completions with everything else when the user starts again")
    func aFreshInstallHasNoCompletions() {
        #expect(SettingsReset.everything.targets.contains(.everySuggestion))
        #expect(!SettingsReset.learnedWords.targets.contains(.everySuggestion))
    }

    @Test("offers the button only where there is something to forget, and counts it first")
    func offeredOnlyWhereThereIsSomething() throws {
        var settings = switchedOn()
        settings.suggestions.set(xcode, isOn: true)
        let shown = pane(settings, personalisation: learned)
        let forget = try #require(row("forgetSuggestions.\(xcode)", in: shown))
        #expect(forget.explanation?.contains("214 completions") == true)
        #expect(forget.explanation?.contains("Xcode") == true)
        #expect(forget.isEnabled)

        #expect(row("forgetSuggestions.\(xcode)", in: pane(settings)) == nil)
    }

    @Test("says what is still there when the disk refuses")
    func saysWhatSurvivedAFailure() {
        let reason = SettingsEditor.reason(forFailed: .suggestions(inApplication: xcode))
        #expect(reason.contains("nothing was forgotten"))
    }

    @Test("refuses a button that has gone stale since the window opened")
    func refusesAStaleButton() {
        var session = SettingsSession(settings: switchedOn(), personalisation: .nothing)
        let removal = SettingsRemoval(
            reset: .suggestions(inApplication: xcode), title: "Forget", confirmation: nil)
        #expect(session.request(removal) == nil)
        #expect(session.rejection?.contains("Xcode") == true)
    }

    @Test("carries the reset out against the corpus, and leaves every other application alone")
    func carriesOutAgainstTheCorpus() async throws {
        try await inACorpusDirectory { directory in
            let corpus = InMemoryCorpus([xcode: 214, notes: 3])
            let store = personalisationStore(in: directory, corpus: corpus)

            try await store.carryOut(.suggestions(inApplication: xcode))
            #expect(corpus.contents == [notes: 3])

            try await store.carryOut(.everything)
            #expect(corpus.contents.isEmpty)
        }
    }

    @Test("counts what each application has taught, so a button can say what it will take")
    func countsWhatEachApplicationTaught() async throws {
        try await inACorpusDirectory { directory in
            let corpus = InMemoryCorpus([xcode: 214])
            let counts = await personalisationStore(in: directory, corpus: corpus)
                .personalisation(keeping: Retention(days: 7, now: noon))
            #expect(counts.suggestions(from: "com.apple.dt.Xcode") == 214)
            #expect(counts.applicationsWithSuggestions == [xcode])
            #expect(!counts.isEmpty)
        }
    }

    @Test("finishes without a corpus, which a build with the feature unwired has none of")
    func worksWithoutACorpus() async throws {
        try await inACorpusDirectory { directory in
            let store = personalisationStore(in: directory, corpus: nil)
            try await store.carryOut(.suggestions(inApplication: xcode))
            let counts = await store.personalisation(keeping: Retention(days: 7, now: noon))
            #expect(counts.suggestions.isEmpty)
            #expect(counts.isEmpty)
        }
    }
}

/// A directory of its own for each test, so nothing here reaches the runner's own files.
private func inACorpusDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = URL.temporaryDirectory.appending(
        path: "uttrflow-suggestions-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}

private func personalisationStore(
    in directory: URL, corpus: (any SuggestionCorpus)?
) -> FilePersonalisationStore {
    FilePersonalisationStore(
        dictionary: PersonalDictionaryStore(file: directory.appending(path: "dictionary.json")),
        history: DictationHistoryStore(file: directory.appending(path: "history.json")),
        clipboard: ClipboardStore(file: directory.appending(path: "clipboard.json")),
        suggestions: corpus)
}

// MARK: - The menu bar's three switches

@Suite("The menu bar's three switches")
struct MenuBarFeatureTests {
    @Test("offers all three, always, so switching one off cannot hide another")
    func allThreeAreAlwaysOffered() {
        let shown = MenuBarPresenter.present(
            MenuBarState(features: MenuBarFeatures(dictation: false, clipboard: false)))
        let titles = shown.commands.map(\.title)
        for feature in MenuBarFeature.allCases {
            #expect(titles.count(where: { $0 == feature.title }) >= 1)
        }
    }

    @Test("switching suggestions off leaves dictation and the clipboard exactly as they were")
    func switchingOneLeavesTheOthers() {
        let before = MenuBarFeatures(dictation: true, clipboard: true, suggestions: true)
        let after = before.setting(.suggestions, isOn: false)
        #expect(after.dictation == before.dictation)
        #expect(after.clipboard == before.clipboard)
        #expect(!after.suggestions)
    }

    @Test("moves whichever switch it was told to, and only that one")
    func movesOnlyTheOneNamed() {
        let all = MenuBarFeatures(dictation: true, clipboard: true, suggestions: true)
        for feature in MenuBarFeature.allCases {
            let after = all.setting(feature, isOn: false)
            #expect(!after.isOn(feature))
            for other in MenuBarFeature.allCases where other != feature {
                #expect(after.isOn(other))
            }
        }
    }

    @Test("ships suggestions off and the other two on, the same as the settings do")
    func shipsTheSameWayTheSettingsDo() {
        let features = MenuBarFeatures()
        #expect(features.dictation)
        #expect(features.clipboard)
        #expect(!features.suggestions)
    }

    @Test("ticks the switches that are on, and asks for the opposite of what it shows")
    func ticksWhatIsOn() {
        let items = MenuBarPresenter.featureItems(
            for: MenuBarFeatures(dictation: true, clipboard: false, suggestions: true))
        let commands: [MenuBarCommand] = items.compactMap {
            if case .command(let command) = $0 { command } else { nil }
        }
        #expect(commands.map(\.isChecked) == [true, false, true])
        #expect(
            commands.map(\.intent) == [
                .setFeature(.dictation, isOn: false),
                .setFeature(.clipboard, isOn: true),
                .setFeature(.suggestions, isOn: false),
            ])
    }

    @Test("greys the item a switch that is off would otherwise leave doing nothing")
    func anOffSwitchGreysWhatItGoverns() throws {
        let shown = MenuBarPresenter.present(
            MenuBarState(features: MenuBarFeatures(dictation: false, clipboard: false)))
        let start = try #require(shown.commands.first { $0.intent == .startDictation })
        let clipboard = try #require(shown.commands.first { $0.intent == .openClipboard })
        #expect(!start.isEnabled)
        #expect(!clipboard.isEnabled)

        let on = MenuBarPresenter.present(MenuBarState())
        #expect(try #require(on.commands.first { $0.intent == .startDictation }).isEnabled)
        #expect(try #require(on.commands.first { $0.intent == .openClipboard }).isEnabled)
    }
}
