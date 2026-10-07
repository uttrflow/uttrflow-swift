// The Settings page as the design lays it out: tabs, search, the General cards, and Diagnostics.

import Foundation
import Testing
import UttrflowCore
import UttrflowSettings

@testable import UttrflowUX

private func pane(
    _ tab: SettingsTab, _ settings: Settings = .default,
    personalisation: SettingsPersonalisation = .nothing
) -> SettingsPane {
    SettingsPresenter.pane(
        for: tab, settings: settings, capabilities: .everything, personalisation: personalisation)
}

private func row(_ id: String, in pane: SettingsPane) -> SettingsRow? {
    pane.groups.flatMap(\.rows).first { $0.id == id }
}

@Suite("The Settings page's tabs")
struct SettingsPageTabTests {
    @Test("six tabs in the design's order, each with its name and symbol")
    func sixTabs() {
        let tabs = SettingsPresenter.tabs()
        #expect(
            tabs.map(\.title)
                == ["General", "Languages", "Dictation", "AI suggestions", "Privacy", "Diagnostics"])
        #expect(
            tabs.map(\.symbolName)
                == ["gearshape", "globe", "mic", "sparkles", "checkmark.shield", "waveform.path.ecg"])
    }

    @Test("Diagnostics has no rows of its own, since the page draws the diagnostics it already holds")
    func diagnosticsIsDrawnElsewhere() {
        let diagnostics = pane(.diagnostics)
        #expect(diagnostics.title == "Diagnostics")
        #expect(diagnostics.groups.isEmpty)
    }
}

@Suite("Searching the Settings page")
struct SettingsSearchTests {
    @Test("an empty query shows the selected tab")
    func blankShowsTheTab() {
        let window = SettingsPresenter.window(showing: .privacy, settings: .default, query: "  ")
        #expect(window.pane.tab == .privacy)
        #expect(window.pane.emptySearch == nil)
    }

    @Test("a query lists every matching row from every tab, under its tab and card")
    func findsAcrossTabs() {
        let window = SettingsPresenter.window(showing: .general, settings: .default, query: "grip")
        let rows = window.pane.groups.flatMap(\.rows).map(\.id)
        #expect(rows == [SettingsToggleField.shrinksToGripWhenIdle.rawValue])
        #expect(window.pane.groups.map(\.title) == ["General · Floating button"])
        #expect(window.query == "grip")
    }

    @Test("matches the words under a row, ignoring case")
    func findsExplanations() {
        let found = SettingsPresenter.search("MINIMISES THE WINDOW", settings: .default)
        #expect(found.groups.flatMap(\.rows).map(\.id) == ["minimisesWhileDictating"])
    }

    @Test("a card whose heading matches keeps every row in it")
    func headingKeepsItsRows() {
        let found = SettingsPresenter.search("floating button", settings: .default)
        let card = found.groups.first { $0.title == "General · Floating button" }
        #expect(card?.rows.count == 4)
    }

    @Test("never lists an add button on its own")
    func leavesAddRowsOut() {
        let found = SettingsPresenter.search("leave alone", settings: .default)
        #expect(!found.groups.flatMap(\.rows).contains { $0.style == .add })
    }

    @Test("says so when nothing matches")
    func saysWhenNothingMatches() {
        let found = SettingsPresenter.search("zebra", settings: .default)
        #expect(found.groups.isEmpty)
        #expect(found.emptySearch == "No setting mentions “zebra”.")
    }

    @Test("the session searches with what is typed")
    func sessionSearches() {
        var session = SettingsSession(settings: .default)
        session.query = "theme"
        #expect(session.presentation.pane.groups.flatMap(\.rows).map(\.id) == ["appearance"])
    }
}

@Suite("The General tab as designed")
struct SettingsGeneralDesignTests {
    @Test("the cards are shortcuts, floating button, sound and startup, updates, then the two features")
    func cards() {
        #expect(
            pane(.general).groups.map(\.title)
                == ["Shortcuts", "Floating button", "Sound & startup", "Updates", "Features"])
    }

    @Test("hands-free sits under Dictate, marked new, with the Dictate keys in its sentence")
    func handsFree() throws {
        let shortcuts = try #require(pane(.general).groups.first)
        #expect(
            shortcuts.rows.map(\.id).prefix(3) == [
                "shortcut.dictate", "handsFreeEnabled", "handsFreeDoubleTapMilliseconds",
            ])
        let handsFree = try #require(row("handsFreeEnabled", in: pane(.general)))
        #expect(handsFree.badge == "NEW")
        #expect(handsFree.style == .inset)
        #expect(handsFree.control == .toggle(field: .handsFreeEnabled, isOn: true))
        let keys = SettingsShortcut.keycaps(for: Settings.default.hotkey)
        #expect(
            handsFree.keyedExplanation
                == SettingsKeyedSentence(
                    before: "Double-tap", keys: keys, after: "to keep listening · tap once to stop"))
        #expect(handsFree.accessibilityLabel.contains("Double-tap"))
        let speed = try #require(row("handsFreeDoubleTapMilliseconds", in: pane(.general)))
        let options = [450, 600, 800].map { milliseconds in
            SettingsOption(
                id: String(milliseconds), title: "\(milliseconds) ms",
                change: .handsFreeDoubleTap(milliseconds: milliseconds))
        }
        #expect(speed.control == .menu(options: options, selectedID: "450"))
        #expect(shortcuts.rows.map(\.id).dropFirst(3).first == "handsFreeHoldMilliseconds")
        let hold = try #require(row("handsFreeHoldMilliseconds", in: pane(.general)))
        #expect(hold.label == "Hold length")
        let holdOptions = [200, 300, 500].map { milliseconds in
            SettingsOption(
                id: String(milliseconds), title: "\(milliseconds) ms",
                change: .handsFreeHold(milliseconds: milliseconds))
        }
        #expect(hold.control == .menu(options: holdOptions, selectedID: "200"))
    }

    @Test("the hands-free switch follows the setting and turns it off")
    func handsFreeIsASwitch() throws {
        var settings = Settings.default
        settings.handsFreeEnabled = false
        #expect(
            row("handsFreeEnabled", in: pane(.general, settings))?.control
                == .toggle(field: .handsFreeEnabled, isOn: false))
        let off = try SettingsEditor.apply(.toggle(.handsFreeEnabled, isOn: false), to: .default)
        #expect(!off.handsFreeEnabled)
    }

    @Test("pressing to toggle has no hands-free row, and Dictate says how it works then")
    func toggleHasNoHandsFree() {
        var settings = Settings.default
        settings.hotkeyActivation = .pressToToggle
        #expect(row("handsFreeEnabled", in: pane(.general, settings)) == nil)
        #expect(
            row("shortcut.dictate", in: pane(.general, settings))?.explanation
                == "Press ⌃⌥ once to start talking, and again to stop")
        #expect(row("shortcut.dictate", in: pane(.general))?.explanation == "Hold ⌃⌥ to talk, anywhere")
    }

    @Test("a held chord of modifiers names its own keys, and only Fn gets the Fn advice")
    func dictateNamesTheUsersKeys() {
        var settings = Settings.default
        settings.hotkey = HotkeyBinding(keyCode: 58, modifiers: [.control, .option])
        let chord = row("shortcut.dictate", in: pane(.general, settings))?.explanation
        #expect(chord == "Hold ⌃⌥ to talk, anywhere")
        #expect(chord?.contains("fn") == false)

        settings.hotkey = .functionHold
        let function = row("shortcut.dictate", in: pane(.general, settings))?.explanation
        #expect(function?.contains("fn") == true)
    }

    @Test("every shortcut row has a tile, and holding is offered both ways")
    func tiles() {
        let shortcuts = pane(.general).groups[0].rows.filter { $0.style == .standard }
        #expect(shortcuts.allSatisfy { $0.icon != nil })
        #expect(row("activation", in: pane(.general))?.label == "How holding works")
    }
}

@Suite("The Dictation tab as designed")
struct SettingsDictationDesignTests {
    @Test("counts the words Uttrflow knows and opens the Dictionary")
    func learnedWords() throws {
        let counted = try #require(
            row(
                "learnedWords",
                in: pane(
                    .dictation,
                    personalisation: SettingsPersonalisation(learnedWords: 20, addedWords: 4, transcripts: 0))
            ))
        #expect(counted.explanation == "24 names and terms")
        #expect(counted.control == .action(title: "Open Dictionary", change: .openPage(.dictionary)))
        #expect(row("learnedWords", in: pane(.dictation))?.explanation?.contains("appear here") == true)
    }

    @Test("offers local export and merge controls for the personal lists")
    func personalDataTransfer() throws {
        let export = try #require(row("exportPersonalData", in: pane(.dictation)))
        let `import` = try #require(row("importPersonalData", in: pane(.dictation)))
        #expect(export.control == .action(title: "Export…", change: .exportPersonalData))
        #expect(`import`.control == .action(title: "Import…", change: .importPersonalData))
        #expect(SettingsChange.exportPersonalData.isRequestToAct)
        #expect(SettingsChange.importPersonalData.isRequestToAct)
    }

    @Test("an app's own row carries its icon")
    func appIcons() {
        let last = SettingsApp(bundleIdentifier: "com.example.notes", name: "Notes")
        let places = SettingsDestinations.places(.none, lastApp: last)
        #expect(places.rows.first?.icon == .application(bundleIdentifier: "com.example.notes", name: "Notes"))
    }
}

@Suite("The Diagnostics tab's cards")
struct DiagnosticsModelCardTests {
    private func page(_ snapshot: DiagnosticsSnapshot) -> DiagnosticsPresentation {
        DiagnosticsPresenter.page(for: snapshot, locale: Locale(identifier: "en_GB"))
    }

    @Test("one card per model, in the design's order, never naming a product")
    func threeCards() {
        let models = page(DiagnosticsSnapshot()).models
        #expect(models.map(\.title) == ["Speech", "Clean-up", "AI suggestions"])
        #expect(models.allSatisfy { $0.chips.contains("On-device") || $0.title == "Clean-up" })
    }

    @Test("the downloaded recogniser says whether it is there and in use")
    func downloadedSpeech() {
        let missing = page(
            DiagnosticsSnapshot(
                speechModel: DiagnosticsModelPresence(
                    isInstalled: false, bytesOnDisk: nil, isMultilingual: true)))
        #expect(missing.models[0].status == "Not downloaded")
        #expect(missing.models[0].state == .attention)
        #expect(missing.models[0].name == "Speech model to download")
        #expect(!missing.models[0].name.hasPrefix("Downloaded"))

        let present = page(
            DiagnosticsSnapshot(
                speechModel: DiagnosticsModelPresence(
                    isInstalled: true, bytesOnDisk: 632_000_000, isMultilingual: true)))
        #expect(present.models[0].status == "In use")
        #expect(present.models[0].name == "Downloaded speech model")
        #expect(present.models[0].chips.contains("Every language"))
    }

    @Test("clean-up names the engine answering first, or says it is still checking")
    func cleanUp() {
        #expect(page(DiagnosticsSnapshot()).models[1].status == "Checking")
        let ready = page(DiagnosticsSnapshot(transformerAvailability: [.foundationModels: true]))
        #expect(ready.models[1].name == "Built-in language model")
        #expect(ready.models[1].status == "Ready")
    }

    @Test(
        "the suggestions card follows the model's readiness",
        arguments: [
            (SuggestionModelReadiness.notAsked, "Off"),
            (.downloading(fractionCompleted: 0.4), "Downloading 40%"),
            (.downloading(fractionCompleted: nil), "Downloading"), (.loading, "Loading"), (.ready, "Loaded"),
            (.releasedForMemory, "Set aside for memory"), (.failed, "Could not be fetched"),
        ])
    func suggestions(readiness: SuggestionModelReadiness, status: String) throws {
        let models = page(DiagnosticsSnapshot(suggestionModel: readiness)).models
        try #require(models.count == 3)
        #expect(models[2].status == status)
    }

    @Test("this Mac lists the build and the machine only when they are known, and the report carries them")
    func thisMac() {
        #expect(page(DiagnosticsSnapshot()).system.isEmpty)
        let snapshot = DiagnosticsSnapshot(
            version: AppVersion(short: "26.0927.0", build: "12"), machine: "26.1 · Apple M3 · 16 GB")
        #expect(page(snapshot).system.map(\.detail) == ["v26.0927.0", "26.1 · Apple M3 · 16 GB"])
        let report = DiagnosticsPresenter.report(for: snapshot)
        #expect(report.contains("Uttrflow: v26.0927.0"))
        #expect(report.contains("macOS: 26.1 · Apple M3 · 16 GB"))
        #expect(report.contains("AI suggestions: Off"))
    }
}
