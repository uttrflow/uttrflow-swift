public import struct Foundation.Date
public import UttrflowCore
public import UttrflowSettings

/// The Settings window while it is open, as a value that decides everything and saves nothing.
public struct SettingsSession: Sendable, Equatable {
    /// What the user has now. Only ever a state ``SettingsEditor`` allowed.
    public private(set) var settings: Settings

    /// What this Mac can do, which changes under the window as downloads and permissions land.
    public var capabilities: SettingsCapabilities

    /// How much of this user is in the app, kept current so a count matches what its button removes.
    public var personalisation: SettingsPersonalisation

    /// Which tab is showing.
    public var tab: SettingsTab

    /// The shortcut field's own state, which is not a setting until it is committed.
    public private(set) var recorder: SettingsShortcutRecorder

    /// Why the last change was refused, until the next one replaces it.
    public private(set) var rejection: String?

    /// What the user has been asked to confirm; nothing is removed while this is set.
    public private(set) var pendingRemoval: SettingsRemoval?

    /// Opens a session on the given settings, at the general tab unless told otherwise.
    public init(
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing,
        tab: SettingsTab = .general
    ) {
        self.settings = settings
        self.capabilities = capabilities
        self.personalisation = personalisation
        self.tab = tab
        self.recorder = SettingsShortcutRecorder(binding: settings.hotkey)
    }

    /// The window as it stands now.
    public var presentation: SettingsWindowPresentation {
        presentation(at: Date())
    }

    /// The window as it stands at one moment, which the half-hour pause is the whole reason for.
    public func presentation(at moment: Date) -> SettingsWindowPresentation {
        SettingsPresenter.window(
            showing: tab, settings: settings, capabilities: capabilities,
            personalisation: personalisation, at: moment)
    }

    /// Carries out a change and returns the settings to save, or records the refusal's reason.
    @discardableResult
    public mutating func apply(_ change: SettingsChange, at moment: Date = Date()) -> Settings? {
        do {
            settings = try SettingsEditor.apply(
                change, to: settings, given: capabilities, at: moment)
        } catch {
            rejection = error.reason
            return nil
        }
        rejection = nil
        // The field follows the setting however the change arrived, so the window never lags it.
        if recorder.binding != settings.hotkey {
            recorder = SettingsShortcutRecorder(binding: settings.hotkey)
        }
        return settings
    }

    /// Says why the shortcut cannot be changed right now, which the field shows in place of a key.
    public mutating func rejectShortcut(_ reason: String) {
        rejection = reason
    }

    /// Takes one keystroke and applies whatever it earned.
    @discardableResult
    public mutating func receive(_ stroke: KeyStroke) -> Settings? {
        settle(recorder.receive(stroke))
    }

    /// Takes a modifier going down; nothing is earned until it is known what it belongs to.
    @discardableResult
    public mutating func hold(keyCode: UInt16, modifiers: Set<HotkeyModifier>) -> Settings? {
        settle(recorder.hold(keyCode: keyCode, modifiers: modifiers))
    }

    /// Takes every modifier coming up, which settles a modifier that was held on its own.
    @discardableResult
    public mutating func release() -> Settings? {
        settle(recorder.release())
    }

    /// Applies whatever an outcome earned, which is the same for every way one is reached.
    private mutating func settle(_ outcome: SettingsShortcutOutcome) -> Settings? {
        switch outcome {
        case .recorded(let change):
            return apply(change)
        case .refused(let refusal):
            rejection = refusal.reason
            return nil
        case .cancelled, .ignored:
            rejection = nil
            return nil
        }
    }

    /// Takes a hardware key code and its modifiers, and applies whatever the keystroke earned.
    @discardableResult
    public mutating func record(
        keyCode: UInt16, modifiers: Set<HotkeyModifier>
    ) -> Settings? {
        settle(recorder.record(keyCode: keyCode, modifiers: modifiers))
    }

    // MARK: - Forgetting

    /// Asks for something to be removed, returning the reset to run now or posting a question.
    @discardableResult
    public mutating func request(_ removal: SettingsRemoval) -> SettingsReset? {
        // The gate the row was drawn from, asked again, since a button can go stale while it sits.
        if let reason = SettingsEditor.unavailability(of: removal.reset, given: personalisation) {
            rejection = reason
            return nil
        }
        rejection = nil
        // `SettingsReset.isConfirmed` is the rule; the row only carries the wording.
        guard removal.confirmation == nil, !removal.reset.isConfirmed else {
            pendingRemoval = removal
            return nil
        }
        return removal.reset
    }

    /// The user said yes; takes the removal the question was drawn with, not the pending one.
    @discardableResult
    public mutating func confirm(_ removal: SettingsRemoval) -> SettingsReset? {
        pendingRemoval = nil
        guard removal.confirmation != nil else { return nil }
        return removal.reset
    }

    /// Whether a removal can be asked about, which a confirmed one needs before it may run.
    public static func isAnswerable(_ removal: SettingsRemoval) -> Bool {
        !removal.reset.isConfirmed || removal.confirmation != nil
    }

    /// The user said no, or dismissed the question. Nothing is removed.
    public mutating func dismissRemoval() {
        pendingRemoval = nil
    }

    /// Records a finished reset against the counts read back from the stores.
    @discardableResult
    public mutating func completed(
        _ reset: SettingsReset, leaving personalisation: SettingsPersonalisation
    ) -> Settings? {
        self.personalisation = personalisation
        pendingRemoval = nil
        rejection = nil
        guard reset.targets.contains(.preferences) else { return nil }
        settings = .default
        // The field follows the setting, so the screen never shows a shortcut that does nothing.
        recorder = SettingsShortcutRecorder(binding: settings.hotkey)
        return settings
    }

    /// A reset could not be finished, said out loud rather than swallowed.
    public mutating func failed(_ reset: SettingsReset) {
        pendingRemoval = nil
        rejection = SettingsEditor.reason(forFailed: reset)
    }

    // MARK: - The shortcut field

    /// Puts the shortcut field into recording, where the next keystroke becomes a binding.
    public mutating func beginRecordingShortcut() {
        rejection = nil
        recorder.beginRecording()
    }

    /// Leaves recording with the shortcut unchanged.
    public mutating func cancelRecordingShortcut() {
        rejection = nil
        recorder.cancel()
    }
}
