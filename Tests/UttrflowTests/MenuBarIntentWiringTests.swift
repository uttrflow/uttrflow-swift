// Tests that every menu bar item, signed in, reaches what it names, and a row that is gone reaches nothing.

import Foundation
import Testing
import UttrflowCore
import UttrflowSettings
import UttrflowUX

@testable import Uttrflow

/// What choosing an item does in a fresh signed-in app, read without a window, a microphone or the defaults.
private enum Reach: Equatable {
    /// Opens this surface.
    case opens(UttrflowUX.AppLocation)
    /// Leaves the app as it was, because a fresh app has no row at that position.
    case nothing
    /// Saves the switch it ticks, so Settings and the menu read back what was chosen.
    case savesSwitch
    /// Saves the Settings edits it carries, as Settings itself would.
    case savesSettings
    /// Reaches the microphone, System Settings, a popover or the process, so no headless test drives it.
    case system
}

/// What each item is expected to do; exhaustive on purpose, so a new item cannot be added without saying.
private func reach(of intent: MenuBarIntent) -> Reach {
    switch intent {
    case .open(let destination): .opens(destination)
    // A fresh app has no speech model, and only onboarding downloads one.
    case .recover(.downloadSpeechModel): .opens(.onboarding)
    case .recover(.retryFromRecording), .recover(.showHistory): .opens(.main(.history))
    case .recover(.openSystemSettings), .recover(.retry), .recover(.pasteManually),
        .recover(.copyTranscript):
        .system
    // Offered only by the floating button, so from the menu with nothing discarded it only dismisses.
    case .recover(.restoreRecording): .nothing
    case .insertRecent, .copyRecent, .insertClip, .copyClip, .undoLearnedWord: .nothing
    case .setFeature: .savesSwitch
    case .changeSettings: .savesSettings
    case .startDictation, .stopDictation, .openClipboard, .checkForUpdates, .quit: .system
    }
}

/// Names an item's case without its payload; exhaustive, so the sample count below means every case.
private func name(of intent: MenuBarIntent) -> String {
    switch intent {
    case .startDictation: "startDictation"
    case .stopDictation: "stopDictation"
    case .recover: "recover"
    case .insertRecent: "insertRecent"
    case .copyRecent: "copyRecent"
    case .insertClip: "insertClip"
    case .copyClip: "copyClip"
    case .undoLearnedWord: "undoLearnedWord"
    case .open: "open"
    case .openClipboard: "openClipboard"
    case .setFeature: "setFeature"
    case .changeSettings: "changeSettings"
    case .checkForUpdates: "checkForUpdates"
    case .quit: "quit"
    }
}

/// How many cases ``MenuBarIntent`` has, bumped deliberately when one is added.
private let menuBarIntentCaseCount = 14

/// Every surface a menu item can name.
private let everyDestination: [UttrflowUX.AppLocation] =
    [.onboarding] + SettingsTab.allCases.map { .settings($0) } + MainTab.allCases.map { .main($0) }

/// Every item at least once, with each page, each fix and a first and a far row position.
private let samples: [MenuBarIntent] =
    [
        .startDictation, .stopDictation, .openClipboard, .setFeature(.dictation, isOn: false),
        .changeSettings([.pauseSuggestions(isOn: false)]), .checkForUpdates, .quit,
    ]
    + everyDestination.map { .open($0) }
    + [
        .recover(.openSystemSettings(.microphone)), .recover(.retry), .recover(.downloadSpeechModel),
        .recover(.pasteManually), .recover(.showHistory), .recover(.retryFromRecording),
        .recover(.restoreRecording), .recover(.copyTranscript),
    ]
    + [UUID(), UUID()].flatMap { id -> [MenuBarIntent] in
        [
            .insertRecent(id: id), .copyRecent(id: id), .insertClip(id: id),
            .copyClip(id: id), .undoLearnedWord(id: id),
        ]
    }

/// A signed-in app that draws nothing, so where a request went is read rather than seen.
@MainActor
private func signedInApp(in sandbox: borrowing Sandbox) -> AppDelegate {
    let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
    app.drawsWindows = false
    return app
}

/// Every menu tick, chosen both ways.
private let everyFeatureSwitch: [MenuBarIntent] = MenuBarFeature.allCases.flatMap { feature in
    [true, false].map { MenuBarIntent.setFeature(feature, isOn: $0) }
}

@MainActor
@Suite("Every menu bar item, signed in", .serialized)
struct MenuBarIntentWiringTests {
    @Test("every case has a sample, so a new item cannot be added without saying what it does")
    func everyCaseHasASample() {
        #expect(Set(samples.map(name(of:))).count == menuBarIntentCaseCount)
    }

    @Test(
        "an item that names a surface opens that surface",
        arguments: samples.filter { if case .opens = reach(of: $0) { true } else { false } })
    func opensWhatItNames(intent: MenuBarIntent) {
        let sandbox = Sandbox()
        let app = signedInApp(in: sandbox)

        guard case .opens(let expected) = reach(of: intent) else {
            Issue.record("\(intent) names no surface")
            return
        }

        app.carryOut(intent)

        #expect(app.lastOpened == expected)
    }

    @Test(
        "a row position the menu no longer holds opens nothing, copies nothing and opens no panel",
        arguments: samples.filter { reach(of: $0) == .nothing })
    func aRowThatIsGoneReachesNothing(intent: MenuBarIntent) async {
        let sandbox = Sandbox()
        let app = signedInApp(in: sandbox)

        app.carryOut(intent)
        await app.intentWork?.value

        #expect(app.lastOpened == nil)
        #expect(app.actionNotice == nil)
        #expect(!app.isQuickPanelOpen)
    }

    @Test("a feature tick saves the switch it names, both ways", arguments: everyFeatureSwitch)
    func aFeatureTickSavesItsSwitch(intent: MenuBarIntent) throws {
        guard case .setFeature(let feature, let isOn) = intent, reach(of: intent) == .savesSwitch else {
            Issue.record("\(intent) saves no switch")
            return
        }
        let store = UserDefaultsSettingsStore(store: ModelDownloadSettingsStore())
        store.save(try SettingsEditor.apply(.toggle(feature.setting, isOn: !isOn), to: .default))
        let sandbox = Sandbox()
        let app = AppDelegate(
            container: sandbox.root, settingsStore: store, account: HeldSession(signedIn: true).layer,
            prepareModel: { _ in })
        app.drawsWindows = false

        app.carryOut(intent)

        #expect(MenuBarFeatures(store.load()).isOn(feature) == isOn)
    }

    @Test("an unticked suggestions item, paused and off in the last app, ticks on in one choice")
    func anUntickedSuggestionsItemTicksOn() throws {
        let application = "com.example.notes"
        let store = UserDefaultsSettingsStore(store: ModelDownloadSettingsStore())
        let sandbox = Sandbox()
        let app = AppDelegate(
            container: sandbox.root, settingsStore: store, account: HeldSession(signedIn: true).layer,
            prepareModel: { _ in })
        app.drawsWindows = false
        app.carryOut(.setFeature(.suggestions, isOn: true))
        app.carryOut(
            .changeSettings([
                .pauseSuggestions(isOn: true), .suggestionsHere(application: application, isOn: false),
            ]))
        let held = MenuBarPresenter.present(
            MenuBarState(features: MenuBarFeatures(store.load(), applicationBundleIdentifier: application)))
        let item = try #require(
            held.commands.first { if case .changeSettings = $0.intent { true } else { false } })
        #expect(!item.isChecked)

        app.carryOut(item.intent)

        #expect(MenuBarFeatures(store.load(), applicationBundleIdentifier: application).suggestions)
    }
}
