// Tests for an editing session over the settings window.
import UttrflowCore
import UttrflowSettings
import Testing

@testable import UttrflowUX

@Suite("An editing session")
struct SettingsSessionTests {
    @Test("opens on the tab it was asked for, showing what is stored")
    func opensWhereItWasAsked() {
        var stored = Settings.default
        stored.floatingButtonAnchor = .rightEdge
        let session = SettingsSession(settings: stored, tab: .privacy)

        #expect(session.tab == .privacy)
        #expect(session.presentation.selected == .privacy)
        #expect(session.settings.floatingButtonAnchor == .rightEdge)
        #expect(session.rejection == nil)
    }

    @Test("hands back the settings to save when a change is allowed")
    func acceptedChangeIsHandedBackToBeSaved() {
        var session = SettingsSession(settings: .default)
        let saved = session.apply(.anchor(.bottomLeft))

        #expect(saved?.floatingButtonAnchor == .bottomLeft)
        #expect(session.settings.floatingButtonAnchor == .bottomLeft)
        #expect(session.rejection == nil)
    }

    @Test("hands back nothing, and says why, when a change is refused")
    func refusedChangeSavesNothing() {
        var session = SettingsSession(settings: .default)
        let saved = session.apply(.retention(days: 0))

        #expect(saved == nil)
        #expect(session.rejection != nil)
        #expect(session.settings == .default)
    }

    @Test("clears the last refusal as soon as something succeeds")
    func refusalDoesNotLinger() {
        var session = SettingsSession(settings: .default)
        session.apply(.retention(days: 0))
        session.apply(.anchor(.bottomLeft))
        #expect(session.rejection == nil)
    }

    @Test("follows the capabilities of the Mac it is given, as they change")
    func capabilitiesCanChangeWhileOpen() {
        var session = SettingsSession(settings: .default)
        session.capabilities.canPlayRecordingSound = false

        let pane = session.presentation.pane
        let row = pane.groups.flatMap(\.rows).first {
            $0.id == SettingsToggleField.playsSoundWhenRecordingStarts.rawValue
        }
        #expect(row?.isEnabled == false)
        #expect(session.apply(.toggle(.playsSoundWhenRecordingStarts, isOn: true)) == nil)
    }

    @Test("records a new shortcut and hands it back to be saved")
    func recordsAShortcut() {
        var session = SettingsSession(settings: .default)
        session.beginRecordingShortcut()
        let saved = session.record(keyCode: 40, modifiers: [.command, .shift])

        #expect(saved?.hotkey == HotkeyBinding(keyCode: 40, modifiers: [.command, .shift]))
        #expect(session.recorder.binding == saved?.hotkey)
        #expect(!session.recorder.isRecording)
    }

    @Test("saves nothing when the recorded shortcut could not be delivered")
    func refusedShortcutSavesNothing() {
        var session = SettingsSession(settings: .default)
        session.beginRecordingShortcut()

        #expect(session.record(keyCode: 40, modifiers: []) == nil)
        #expect(session.settings.hotkey == Settings.default.hotkey)
        #expect(session.rejection != nil)
    }

    @Test("saves nothing when the user backs out, and stops complaining")
    func cancellingSavesNothing() {
        var session = SettingsSession(settings: .default)
        session.beginRecordingShortcut()
        session.record(keyCode: 40, modifiers: [])
        #expect(session.record(keyCode: 53, modifiers: []) == nil)
        #expect(session.rejection == nil)

        // And a keystroke that arrives when nothing is listening changes nothing either.
        #expect(session.record(keyCode: 8, modifiers: [.command]) == nil)
        #expect(session.settings.hotkey == Settings.default.hotkey)
    }

    @Test("beginning and cancelling both clear the last refusal")
    func recordingStateClearsRefusals() {
        var session = SettingsSession(settings: .default)
        session.apply(.retention(days: 0))
        session.beginRecordingShortcut()
        #expect(session.rejection == nil)
        #expect(session.recorder.isRecording)

        session.apply(.retention(days: 0))
        session.cancelRecordingShortcut()
        #expect(session.rejection == nil)
        #expect(!session.recorder.isRecording)
    }

    @Test("keeps the shortcut field showing what is in force, however it was changed")
    func fieldFollowsTheSetting() {
        var session = SettingsSession(settings: .default)
        let binding = HotkeyBinding(keyCode: 8, modifiers: [.control, .option])
        session.apply(.shortcut(binding))
        #expect(session.recorder.binding == binding)
    }

    @Test("repairs a stored shortcut that could never have been delivered")
    func repairsAnUnusableStoredShortcut() {
        var stored = Settings.default
        // 0x80 is past the 7-bit virtual key range, so no modifier combination can rescue it.
        stored.hotkey = HotkeyBinding(keyCode: 0x80, modifiers: [.option])
        let session = SettingsSession(settings: stored)
        #expect(session.recorder.binding == .optionSpace)
    }

    @Test("shows whichever tab it is switched to, without losing the settings")
    func switchingTabsKeepsTheSettings() {
        var session = SettingsSession(settings: .default)
        session.apply(.anchor(.bottomCentre))
        for tab in SettingsTab.allCases {
            session.tab = tab
            #expect(session.presentation.pane.tab == tab)
            #expect(session.settings.floatingButtonAnchor == .bottomCentre)
        }
    }
}
