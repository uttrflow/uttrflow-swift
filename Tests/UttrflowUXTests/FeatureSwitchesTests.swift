import UttrflowCore
import UttrflowSettings
import Testing

@testable import UttrflowUX

// Tests that the menu's Dictation and Clipboard ticks are stored switches that change what runs.

@Suite("The menu bar's Dictation, Clipboard and AI Suggestions switches")
struct FeatureSwitchesTests {
    /// Each tick is written through the same editor the Settings window uses, so it is stored.
    @Test(
        "switching a feature off in the menu stores it off, and the menu reads it back",
        arguments: MenuBarFeature.allCases)
    func menuTickIsStored(feature: MenuBarFeature) throws {
        var start = Settings.default
        start.suggestions.isEnabled = true

        let off = try SettingsEditor.apply(.toggle(feature.setting, isOn: false), to: start)
        let on = try SettingsEditor.apply(.toggle(feature.setting, isOn: true), to: off)

        #expect(!MenuBarFeatures(off).isOn(feature))
        #expect(MenuBarFeatures(on).isOn(feature))
        // Moving one switch leaves the other two where they were.
        for other in MenuBarFeature.allCases where other != feature {
            #expect(MenuBarFeatures(off).isOn(other) == MenuBarFeatures(start).isOn(other))
        }
    }

    @Test("the menu starts with dictation and clipboard on and suggestions off")
    func defaults() {
        #expect(MenuBarFeatures(Settings.default) == MenuBarFeatures())
    }

    @Test("turning the clipboard off releases its shortcut and keeps the others")
    func clipboardOffReleasesItsShortcut() {
        var settings = Settings.default
        settings.clipboardEnabled = false

        let armed = ShortcutRegistry.claimed(in: settings).map(\.action)

        #expect(!armed.contains(.clipboard))
        #expect(armed.contains(.pasteLastTranscript))
        #expect(armed.contains(.copyLastTranscript))
        #expect(ShortcutRegistry.claimed(in: .default).map(\.action).contains(.clipboard))
    }

    @Test("turning dictation off hides the floating button, whatever the button's own switch says")
    func dictationOffHidesTheButton() {
        var settings = Settings.default
        #expect(settings.floatingButtonIsShown)

        settings.dictationEnabled = false
        #expect(!settings.floatingButtonIsShown)

        settings.dictationEnabled = true
        settings.showsFloatingButton = false
        #expect(!settings.floatingButtonIsShown)
    }

    @Test("Settings shows the same two switches the menu does")
    func settingsShowsTheSwitches() {
        var settings = Settings.default
        settings.clipboardEnabled = false
        let pane = SettingsPresenter.pane(for: .general, settings: settings)
        let rows = pane.groups.flatMap(\.rows)

        let dictation = rows.first { $0.id == SettingsToggleField.dictationEnabled.rawValue }
        let clipboard = rows.first { $0.id == SettingsToggleField.clipboardEnabled.rawValue }
        #expect(dictation?.control == .toggle(field: .dictationEnabled, isOn: true))
        #expect(clipboard?.control == .toggle(field: .clipboardEnabled, isOn: false))
    }
}
