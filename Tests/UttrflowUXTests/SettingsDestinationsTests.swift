import Testing
import UttrflowCore
import UttrflowSettings

@testable import UttrflowUX

@Suite("Switching a clean-up step off, in Settings")
struct SettingsCleaningStepsTests {
    private func pane(_ settings: Settings) -> SettingsPane {
        SettingsPresenter.pane(for: .dictation, settings: settings)
    }

    private func steps(_ settings: Settings) -> SettingsGroup? {
        pane(settings).groups.first { $0.id == "cleaningSteps" }
    }

    @Test("every step is offered, ticked, in the order it runs")
    func everyStepIsOffered() throws {
        let group = try #require(steps(.default))
        #expect(group.rows.map(\.label) == CleaningSteps.offered.map(\.name))
        for row in group.rows {
            guard case .tick(let isTicked, _) = row.control else {
                Issue.record("\(row.label) is not a tick")
                continue
            }
            #expect(isTicked)
        }
    }

    @Test("the tick reports the change that switches the step the other way")
    func tickReportsTheChange() throws {
        let group = try #require(steps(.default))
        let row = try #require(group.rows.first)
        guard case .tick(_, let change) = row.control else {
            Issue.record("the first row is not a tick")
            return
        }
        #expect(change == .cleaningStep(.fillers, isOn: false))
    }

    @Test("a step switched off is drawn unticked, and offers to switch it back on")
    func switchedOffIsDrawnOff() throws {
        var settings = Settings.default
        settings.cleaning = CleaningSteps.default.setting(.fillers, isOn: false)
        let row = try #require(steps(settings)?.rows.first)
        #expect(row.control == .tick(isTicked: false, change: .cleaningStep(.fillers, isOn: true)))
    }

    @Test("the editor is the only thing that writes the choice down")
    func editorApplies() throws {
        let off = try SettingsEditor.apply(
            .cleaningStep(.fillers, isOn: false), to: .default)
        #expect(!off.cleaning.runs(.fillers))
        let on = try SettingsEditor.apply(.cleaningStep(.fillers, isOn: true), to: off)
        #expect(on.cleaning.runs(.fillers))
    }

    /// The first word's case and the final stop belong to the place the words are going.
    @Test("a step the formatter owns is refused rather than silently ignored")
    func policyStepIsRefused() {
        #expect(throws: SettingsRejection.self) {
            try SettingsEditor.apply(.cleaningStep(.firstWord, isOn: false), to: .default)
        }
    }
}

@Suite("Treating one app as somewhere else, in Settings")
struct SettingsDestinationsTests {
    private let slack = SettingsApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")

    private func places(_ settings: Settings, lastApp: SettingsApp?) -> SettingsGroup? {
        SettingsPresenter.pane(
            for: .dictation, settings: settings,
            personalisation: SettingsPersonalisation(
                learnedWords: 0, addedWords: 0, transcripts: 0, lastDictationApp: lastApp)
        ).groups.first { $0.id == "places" }
    }

    @Test("with nothing dictated yet the row says so rather than offering a choice about nothing")
    func nothingYet() throws {
        let group = try #require(places(.default, lastApp: nil))
        #expect(group.rows.count == 1)
        #expect(group.rows.first?.control == .text("Nothing yet"))
    }

    @Test("the app last dictated into is offered every kind of place, and working it out")
    func offersEveryKind() throws {
        let row = try #require(places(.default, lastApp: slack)?.rows.first)
        #expect(row.label == "Slack")
        guard case .menu(let options, let selected) = row.control else {
            Issue.record("the row is not a pop-up")
            return
        }
        #expect(selected == SettingsDestinations.automaticID)
        #expect(options.first?.title == "Work it out")
        #expect(options.count == UttrflowCore.Destination.allCases.count + 1)
    }

    @Test("an app with an override shows the kind it was given")
    func showsTheOverride() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none.setting(
            .document, for: slack.bundleIdentifier, named: "Slack")
        let row = try #require(places(settings, lastApp: slack)?.rows.first)
        guard case .menu(_, let selected) = row.control else {
            Issue.record("the row is not a pop-up")
            return
        }
        #expect(selected == UttrflowCore.Destination.document.rawValue)
    }

    @Test("every override made is listed, with a way to put it back")
    func listsTheOverrides() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none
            .setting(.document, for: "com.example.Zebra", named: "Zebra")
            .setting(.codeEditor, for: "com.example.Apricot", named: "Apricot")
        let rows = try #require(places(settings, lastApp: nil)?.rows.dropFirst())
        #expect(rows.map(\.label) == ["Apricot", "Zebra"])
        #expect(rows.first?.explanation == "Treated as code.")
        #expect(
            rows.first?.control
                == .action(
                    title: "Use the Default",
                    change: .forgetAppDestination(bundleIdentifier: "com.example.Apricot")))
    }

    @Test("choosing a kind stores it against the app, and working it out takes it back")
    func editorApplies() throws {
        let chosen = try SettingsEditor.apply(
            .appDestination(
                bundleIdentifier: slack.bundleIdentifier, name: "Slack", destination: .document),
            to: .default)
        #expect(chosen.destinations.destination(forBundleIdentifier: slack.bundleIdentifier) == .document)

        let forgotten = try SettingsEditor.apply(
            .forgetAppDestination(bundleIdentifier: slack.bundleIdentifier), to: chosen)
        #expect(forgotten.destinations.isEmpty)
    }

    @Test("an override with no app to be about is refused")
    func refusesAnEmptyIdentifier() {
        #expect(throws: SettingsRejection.self) {
            try SettingsEditor.apply(
                .appDestination(bundleIdentifier: "", name: nil, destination: .document),
                to: .default)
        }
    }

    @Test("an app the screen never named is offered by its identifier")
    func unnamedApp() {
        let app = SettingsApp(bundleIdentifier: "com.example.App")
        #expect(app.title == "com.example.App")
        #expect(SettingsApp(bundleIdentifier: "com.example.App", name: "").title == "com.example.App")
    }

    @Test("every kind of place has a plain name")
    func everyKindIsNamed() {
        for destination in SettingsDestinations.offered {
            #expect(!SettingsDestinations.title(of: destination).isEmpty)
        }
        #expect(SettingsDestinations.title(of: .spreadsheet) == "A spreadsheet cell")
        #expect(SettingsDestinations.title(of: .messaging) == "A chat")
        #expect(SettingsDestinations.title(of: .email) == "An email")
        #expect(SettingsDestinations.title(of: .sqlEditor) == "A SQL editor")
        #expect(SettingsDestinations.title(of: .plain) == "Plain text")
    }
}
