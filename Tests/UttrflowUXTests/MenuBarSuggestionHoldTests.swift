import Foundation
import Testing
import UttrflowPredict
import UttrflowSettings

@testable import UttrflowUX

@Suite("An unticked AI suggestions item lifts what holds suggestions off")
struct MenuBarSuggestionHoldTests {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)
    private let application = "com.example.notes"
    private let privateApplication = SuggestionApplications.privateByDefault[0].bundleIdentifier
    private let shippedEditor = SuggestionApplications.offByDefault[0].bundleIdentifier

    private func settings(
        isEnabled: Bool = true, isPaused: Bool = false, turnedOff: Set<String> = []
    ) -> Settings {
        Settings(
            suggestions: SuggestionPreferences(
                isEnabled: isEnabled, turnedOff: turnedOff,
                pausedUntil: isPaused ? moment.addingTimeInterval(600) : nil))
    }

    private func suggestionsItem(_ settings: Settings, in application: String?) -> MenuBarCommand? {
        let features = MenuBarFeatures(settings, applicationBundleIdentifier: application, at: moment)
        return MenuBarPresenter.featureItems(for: features).compactMap { item -> MenuBarCommand? in
            guard case .command(let command) = item else { return nil }
            return command
        }.last
    }

    /// The settings after the item's edits, applied as the app applies them, one after another.
    private func choosing(_ command: MenuBarCommand?, from settings: Settings) throws -> Settings {
        guard case .changeSettings(let changes) = command?.intent else {
            Issue.record("\(String(describing: command?.intent)) changes no setting")
            return settings
        }
        return try changes.reduce(settings) { try SettingsEditor.apply($1, to: $0, at: moment) }
    }

    @Test("a paused item resumes suggestions, the same edit as Settings' Resume")
    func pausedItemResumes() throws {
        let paused = settings(isPaused: true)
        let item = suggestionsItem(paused, in: nil)

        #expect(item?.isChecked == false)
        #expect(item?.title == "AI Suggestions, Beta — Paused, click to resume")
        let chosen = try choosing(item, from: paused)
        #expect(MenuBarFeatures(chosen, at: moment).suggestions)
        #expect(!chosen.suggestions.isPaused(at: moment))
    }

    @Test("an item off in the last application turns suggestions on there")
    func turnedOffItemTurnsOnHere() throws {
        let turnedOff = settings(turnedOff: [application])
        let item = suggestionsItem(turnedOff, in: application)

        #expect(item?.title == "AI Suggestions, Beta — Off in this app, click to turn on")
        let chosen = try choosing(item, from: turnedOff)
        #expect(MenuBarFeatures(chosen, applicationBundleIdentifier: application, at: moment).suggestions)
    }

    @Test("an item both paused and off in the application lifts both in one choice")
    func pausedAndTurnedOffItemLiftsBoth() throws {
        let both = settings(isPaused: true, turnedOff: [application])
        let item = suggestionsItem(both, in: application)

        #expect(item?.title == "AI Suggestions, Beta — Paused and off in this app, click to turn on")
        let chosen = try choosing(item, from: both)
        #expect(MenuBarFeatures(chosen, applicationBundleIdentifier: application, at: moment).suggestions)
    }

    @Test("an application that ships off opens Settings rather than opting it in, paused or not")
    func shippedOffItemOpensSettings() {
        let cases: [(Settings, String, String)] = [
            (settings(), shippedEditor, "Off in this app, which has its own suggestions; open Settings…"),
            (
                settings(isPaused: true), privateApplication,
                "Off in this app, which holds private information; open Settings…"
            ),
            (
                settings(turnedOff: [privateApplication]), privateApplication,
                "Off in this app, which holds private information; open Settings…"
            ),
            (
                settings(turnedOff: [shippedEditor]), shippedEditor,
                "Off in this app, which has its own suggestions; open Settings…"
            ),
        ]
        for (stored, application, line) in cases {
            let item = suggestionsItem(stored, in: application)
            #expect(item?.intent == .open(.settings(.suggestions)))
            #expect(item?.title == "AI Suggestions, Beta — \(line)")
            #expect(item?.isChecked == false)
        }
    }

    @Test("with the switch itself off, the item turns the switch on and names nothing else")
    func masterOffItemTurnsTheSwitchOn() {
        let item = suggestionsItem(settings(isEnabled: false, isPaused: true), in: application)

        #expect(item?.intent == .setFeature(.suggestions, isOn: true))
        #expect(item?.title == "AI Suggestions, Beta")
    }

    @Test("a ticked item still turns the switch off")
    func tickedItemTurnsTheSwitchOff() {
        let item = suggestionsItem(settings(), in: application)

        #expect(item?.isChecked == true)
        #expect(item?.intent == .setFeature(.suggestions, isOn: false))
    }

    @Test("moving the suggestions switch forgets the hold it was read with")
    func settingTheSwitchClearsTheHold() {
        let paused = MenuBarFeatures(settings(isPaused: true), at: moment)

        #expect(paused.suggestionHold == .paused)
        #expect(paused.setting(.suggestions, isOn: true).suggestionHold == nil)
        #expect(paused.setting(.dictation, isOn: false).suggestionHold == .paused)
    }
}
