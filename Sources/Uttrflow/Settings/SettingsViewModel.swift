// The Settings window's observable state over `SettingsSession`.

import UttrflowCore
import UttrflowHistory
import UttrflowSettings
import UttrflowUX
import SwiftUI

import struct Foundation.Date

/// The Settings window's observable state; every rule lives in `SettingsSession`.
@MainActor
@Observable
final class SettingsViewModel {
    var session: SettingsSession

    /// Who is signed in, for the foot of the rail; set from outside, because the app already holds it.
    var identity: AccountIdentity?

    private let store: any SettingsStore
    private let personalisation: any SettingsPersonalisationStore
    private let onChange: (UttrflowSettings.Settings) -> Void
    private let onReset: (SettingsReset) -> Void
    /// Told when the shortcut field starts and stops listening, so the live shortcut stands down meanwhile.
    private let onShortcutRecording: (Bool) -> Void

    init(
        store: any SettingsStore,
        personalisation: any SettingsPersonalisationStore,
        capabilities: SettingsCapabilities,
        tab: SettingsTab = .general,
        onChange: @escaping (UttrflowSettings.Settings) -> Void = { _ in },
        onReset: @escaping (SettingsReset) -> Void = { _ in },
        onShortcutRecording: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.personalisation = personalisation
        self.onChange = onChange
        self.onReset = onReset
        self.onShortcutRecording = onShortcutRecording
        session = SettingsSession(
            settings: store.load(), capabilities: capabilities, tab: tab)
    }

    /// Starts listening for a new shortcut, and stands the live one down while it does.
    func beginRecordingShortcut() {
        session.beginRecordingShortcut()
        onShortcutRecording(true)
    }

    /// Stops listening and brings the live shortcut back; called from Cancel and from a successful recording.
    func cancelRecordingShortcut() {
        session.cancelRecordingShortcut()
        onShortcutRecording(false)
    }

    /// Saved as each change is made; nothing here is half chosen, so there is nothing for Cancel to undo.
    func apply(_ change: SettingsChange) {
        persist(session.apply(change))
    }

    /// A modifier going down, which the recorder holds until it knows what it is part of.
    func hold(keyCode: UInt16, modifiers: Set<HotkeyModifier>) {
        persist(session.hold(keyCode: keyCode, modifiers: modifiers))
    }

    /// Every modifier coming up, which settles a modifier held on its own.
    func release() {
        persist(session.release())
        if !session.recorder.isRecording {
            onShortcutRecording(false)
        }
    }

    func record(keyCode: UInt16, modifiers: Set<HotkeyModifier>) {
        persist(session.record(keyCode: keyCode, modifiers: modifiers))
        // A recorded shortcut ends the recording; a refusal leaves the field listening, mid-choice.
        if !session.recorder.isRecording {
            onShortcutRecording(false)
        }
    }

    // MARK: - Forgetting

    /// The user pressed a destructive button; whether that removes, asks or refuses is the session's call.
    func request(_ removal: SettingsRemoval) {
        guard let reset = session.request(removal) else { return }
        carryOut(reset)
    }

    /// The user answered yes; the removal is handed in because the alert clears itself as it closes.
    func confirm(_ removal: SettingsRemoval) {
        guard let reset = session.confirm(removal) else { return }
        carryOut(reset)
    }

    func dismissRemoval() {
        session.dismissRemoval()
    }

    /// Reads the counts back off disk on every opening, since the user has been dictating in between.
    func refreshPersonalisation() {
        let promise = retentionInForce
        Task { [personalisation] in
            session.personalisation = await personalisation.personalisation(keeping: promise)
        }
    }

    /// Hands a reset to the stores, then takes the counts back from them.
    private func carryOut(_ reset: SettingsReset) {
        let promise = retentionInForce
        Task { [personalisation] in
            do {
                try await personalisation.carryOut(reset)
            } catch {
                session.failed(reset)
                return
            }
            // Read back rather than assumed zero: what a level removes is the stores' definition.
            persist(
                session.completed(
                    reset, leaving: await personalisation.personalisation(keeping: promise)))
            onReset(reset)
        }
    }

    /// The promise in force, so a count of transcripts is a count of what is still shown.
    private var retentionInForce: Retention {
        Retention(days: session.settings.transcriptRetentionDays, now: Date())
    }

    private func persist(_ settings: UttrflowSettings.Settings?) {
        guard let settings else { return }
        store.save(settings)
        onChange(settings)
    }
}
