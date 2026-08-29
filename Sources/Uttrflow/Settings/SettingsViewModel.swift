import UttrflowCore
import UttrflowHistory
import UttrflowSettings
import UttrflowUX
import SwiftUI

import struct Foundation.Date

/// The Settings window's observable state.
///
/// Deliberately almost empty. Everything the window shows and every rule about what may
/// change lives in ``SettingsSession``, which is a value a test can drive; this adds
/// only the three things a value cannot do — tell SwiftUI something moved, put the
/// result somewhere it survives, and await an actor.
@MainActor
@Observable
final class SettingsViewModel {
    var session: SettingsSession

    /// Who is signed in, for the foot of the rail. `nil` before anybody is, and while
    /// the app has not read the profile yet.
    ///
    /// Set from outside rather than fetched here: this window has no business holding an
    /// authentication service, and the app already keeps the answer for the Account page.
    var identity: AccountIdentity?

    private let store: any SettingsStore
    private let personalisation: any SettingsPersonalisationStore
    private let onChange: (UttrflowSettings.Settings) -> Void
    private let onReset: (SettingsReset) -> Void
    /// Told when the shortcut field starts and stops listening, so the live shortcut can
    /// be stood down while somebody is choosing a new one.
    ///
    /// It matters most for a held modifier. The field's monitor deliberately passes flag
    /// changes on — swallowing them would leave the rest of the app believing a key is
    /// still down — so with Fn bound, pressing Fn to record it also started a real
    /// dictation behind the settings window, which then ran until something else stopped
    /// it. A key press is swallowed and never had this problem.
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

    /// Stops listening, whether or not a shortcut was recorded, and brings the live one
    /// back. Called from both ends: Cancel, and a successful recording.
    func cancelRecordingShortcut() {
        session.cancelRecordingShortcut()
        onShortcutRecording(false)
    }

    /// Saved as each change is made rather than behind an OK button: nothing in this
    /// window is half chosen, so there is nothing for a Cancel to undo.
    func apply(_ change: SettingsChange) {
        persist(session.apply(change))
    }

    func record(keyCode: UInt16, modifiers: Set<HotkeyModifier>) {
        persist(session.record(keyCode: keyCode, modifiers: modifiers))
        // A recorded shortcut ends the recording, so the live one comes back — with the
        // new binding, which `onChange` has already saved. A refusal leaves the field
        // listening and the live shortcut stood down, which is right: the user is still
        // mid-choice.
        if !session.recorder.isRecording {
            onShortcutRecording(false)
        }
    }

    // MARK: - Forgetting

    /// The user pressed a destructive button.
    ///
    /// Whether that removes anything now, asks first, or is refused is
    /// ``SettingsSession/request(_:)``'s decision, not this one's.
    func request(_ removal: SettingsRemoval) {
        guard let reset = session.request(removal) else { return }
        carryOut(reset)
    }

    /// The user answered yes to the question in front of them.
    ///
    /// The removal is handed in rather than read back off the session, because the alert
    /// clears itself as it closes and the two can happen in either order.
    func confirm(_ removal: SettingsRemoval) {
        guard let reset = session.confirm(removal) else { return }
        carryOut(reset)
    }

    func dismissRemoval() {
        session.dismissRemoval()
    }

    /// Reads the counts back off disk.
    ///
    /// Asked on every opening, because the window is kept alive between openings and
    /// the user has been dictating in between.
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
            // Read back rather than assumed to be zero: what a level removes is the
            // stores' definition, and this window's job is to report it, not restate it.
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
