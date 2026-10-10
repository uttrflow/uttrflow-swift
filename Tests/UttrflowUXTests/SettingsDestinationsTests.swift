import Foundation
import Testing
import UttrflowCore
import UttrflowHistory
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
        for (row, step) in zip(group.rows, CleaningSteps.offered) {
            guard case .tick(let isTicked, _) = row.control else {
                Issue.record("\(row.label) is not a tick")
                continue
            }
            #expect(isTicked == step.isOnByDefault)
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
    private let apricot = SettingsApp(bundleIdentifier: "com.example.Apricot", name: "Apricot")

    private func places(_ settings: Settings, recent: [SettingsApp]) -> SettingsGroup? {
        SettingsPresenter.pane(
            for: .dictation, settings: settings,
            personalisation: SettingsPersonalisation(
                learnedWords: 0, addedWords: 0, transcripts: 0, recentDictationApps: recent)
        ).groups.first { $0.id == "places" }
    }

    /// The rows naming an app, without the one that adds another.
    private func appRows(_ settings: Settings, recent: [SettingsApp]) throws -> [SettingsRow] {
        try #require(places(settings, recent: recent)).rows.filter { $0.id != "addApp" }
    }

    private func menu(_ row: SettingsRow?) -> (options: [SettingsOption], selected: String)? {
        guard case .menu(let options, let selected) = row?.control else { return nil }
        return (options, selected)
    }

    @Test("with nothing dictated yet the row says so rather than offering a choice about nothing")
    func nothingYet() throws {
        let rows = try appRows(.default, recent: [])
        #expect(rows.count == 1)
        #expect(rows.first?.control == .placeholder("Nothing yet"))
    }

    @Test("the app last dictated into is offered every kind of place, and working it out")
    func offersEveryKind() throws {
        let row = try appRows(.default, recent: [slack]).first
        #expect(row?.label == "Slack")
        let pop = try #require(menu(row))
        #expect(pop.selected == SettingsDestinations.automaticID)
        #expect(pop.options.first?.title.hasPrefix("Work it out") == true)
        #expect(pop.options.count == UttrflowCore.Destination.allCases.count + 1)
    }

    @Test("working it out names what it works out for that app")
    func automaticNamesTheClassification() throws {
        let rows = try appRows(.default, recent: [slack, apricot])
        #expect(menu(rows.first)?.options.first?.title == "Work it out (a chat)")
        #expect(menu(rows.last)?.options.first?.title == "Work it out (plain text)")
    }

    @Test("working it out names the table's answer even while an override stands")
    func automaticIgnoresTheOverride() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none.setting(
            .document, for: slack.bundleIdentifier, named: "Slack")
        let row = try appRows(settings, recent: [slack]).first
        #expect(menu(row)?.options.first?.title == "Work it out (a chat)")
    }

    @Test("an app with an override shows the kind it was given")
    func showsTheOverride() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none.setting(
            .document, for: slack.bundleIdentifier, named: "Slack")
        let row = try appRows(settings, recent: [slack]).first
        #expect(menu(row)?.selected == UttrflowCore.Destination.document.rawValue)
    }

    @Test("every app in kept history is listed, newest first, each with its own pop-up")
    func listsEveryRecentApp() throws {
        let notes = SettingsApp(bundleIdentifier: "com.example.Notes", name: "Notes")
        let rows = try appRows(.default, recent: [notes, slack, apricot])
        #expect(rows.map(\.label) == ["Notes", "Slack", "Apricot"])
        #expect(rows.allSatisfy { menu($0) != nil })
        let pop = try #require(menu(rows[1]))
        #expect(
            pop.options.contains {
                $0.change
                    == .appDestination(
                        bundleIdentifier: slack.bundleIdentifier, name: "Slack", destination: .document)
            })
    }

    @Test("an app is named once whether it comes from history, an override, or both, by its normalised key")
    func deduplicatesByKey() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none
            .setting(.document, for: "COM.TINYSPECK.SLACKMACGAP", named: "Slack")
            .setting(.codeEditor, for: apricot.bundleIdentifier, named: "Apricot")
        let rows = try appRows(
            settings, recent: [slack, SettingsApp(bundleIdentifier: "Com.Tinyspeck.SlackMacGap")])
        #expect(rows.map(\.label) == ["Slack", "Apricot"])
    }

    @Test("apps from history come first by use, then overrides with no history in a stable order")
    func ordersHistoryThenOverrides() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none
            .setting(.document, for: "com.example.Zebra", named: "Zebra")
            .setting(.codeEditor, for: apricot.bundleIdentifier, named: "Apricot")
        let rows = try appRows(settings, recent: [slack])
        #expect(rows.map(\.label) == ["Slack", "Apricot", "Zebra"])
    }

    @Test("an existing override is changed from its own row, not only reset")
    func overridesAreEditable() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none
            .setting(.codeEditor, for: apricot.bundleIdentifier, named: "Apricot")
        let row = try appRows(settings, recent: [slack]).last
        #expect(row?.label == "Apricot")
        let pop = try #require(menu(row))
        #expect(pop.selected == UttrflowCore.Destination.codeEditor.rawValue)
        let toDocument = try #require(
            pop.options.first { $0.id == UttrflowCore.Destination.document.rawValue })
        let changed = try SettingsEditor.apply(toDocument.change, to: settings)
        #expect(changed.destinations.destination(forBundleIdentifier: apricot.bundleIdentifier) == .document)
        #expect(
            pop.options.first?.change == .forgetAppDestination(bundleIdentifier: apricot.bundleIdentifier))
    }

    @Test("an installed app can be added without dictating into it first")
    func offersThePicker() throws {
        let add = try #require(places(.default, recent: [])?.rows.last)
        #expect(add.id == "addApp")
        guard case .action(_, let change) = add.control else {
            Issue.record("the add row is not a button")
            return
        }
        #expect(change == .chooseApplicationForDestination)
        #expect(change.isRequestToAct)
        #expect(try SettingsEditor.apply(change, to: .default) == .default)
    }

    @Test("an app added from the picker is stored as the table's answer and survives a restart")
    func pickedAppPersists() throws {
        let picked = SettingsApp(bundleIdentifier: "com.example.Picked", name: "Picked")
        let change = SettingsDestinations.adding(picked)
        let added = try SettingsEditor.apply(change, to: .default)
        let reread = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(added))
        #expect(reread.destinations.destination(forBundleIdentifier: "com.example.picked") == .plain)
        let rows = try appRows(reread, recent: [])
        #expect(rows.map(\.label) == ["Picked"])
        #expect(menu(rows.first)?.selected == UttrflowCore.Destination.plain.rawValue)
    }

    @Test("kept history gives every app it went into, newest use first, once each")
    func recentAppsFromHistory() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let records = [
            DictationRecord(
                text: "one", when: start, applicationName: "Slack",
                applicationIdentifier: slack.bundleIdentifier),
            DictationRecord(
                text: "two", when: start.addingTimeInterval(60), applicationName: "Apricot",
                applicationIdentifier: apricot.bundleIdentifier),
            DictationRecord(text: "three", when: start.addingTimeInterval(120)),
            DictationRecord(
                text: "four", when: start.addingTimeInterval(180),
                applicationIdentifier: "COM.TINYSPECK.SLACKMACGAP"),
        ]
        let apps = FilePersonalisationStore.recentApps(in: records)
        #expect(apps.map(\.title) == ["Slack", "Apricot"])
        #expect(apps.first?.bundleIdentifier == "COM.TINYSPECK.SLACKMACGAP")
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
