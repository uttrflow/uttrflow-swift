public import struct Foundation.Date
public import UttrflowCore
public import UttrflowSettings

/// The Settings window while it is open: what it is showing, and the only route by
/// which any of it changes.
///
/// A value, not a screen. Everything that would otherwise accumulate in a view model —
/// which tab, what the shortcut field is doing, why the last change was refused, and
/// what to save — is decided here, so the window has nothing left to decide and a test
/// can drive a whole editing session without a screen.
///
/// It saves nothing itself. ``apply(_:)`` hands back the settings to persist, or
/// nothing at all when the change was refused, which keeps the one side effect in the
/// one place that has somewhere to put it.
public struct SettingsSession: Sendable, Equatable {
    /// What the user has now. Only ever a state ``SettingsEditor`` allowed.
    public private(set) var settings: Settings

    /// What this Mac can do. A `var` because a model can finish downloading, and the
    /// user can allow the login item, while this window is open.
    public var capabilities: SettingsCapabilities

    /// How much of this user is in the app. A `var` for the reason ``capabilities`` is
    /// one: a dictation finishing while this window is open adds to it, and a count
    /// shown beside a destructive button has to be the count that button will act on.
    public var personalisation: SettingsPersonalisation

    /// Which tab is showing.
    public var tab: SettingsTab

    /// The shortcut field's own state, which is not a setting until it is committed.
    public private(set) var recorder: SettingsShortcutRecorder

    /// Why the last change was refused, until the next one replaces it.
    public private(set) var rejection: String?

    /// What the user has been asked to confirm, until they answer.
    ///
    /// Nothing has been removed while this is set. It is the question, not a promise
    /// that the answer will be yes.
    public private(set) var pendingRemoval: SettingsRemoval?

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

    public var presentation: SettingsWindowPresentation {
        presentation(at: Date())
    }

    /// The window as it stands at one moment, which the half-hour pause is the whole reason for.
    public func presentation(at moment: Date) -> SettingsWindowPresentation {
        SettingsPresenter.window(
            showing: tab, settings: settings, capabilities: capabilities,
            personalisation: personalisation, at: moment)
    }

    /// Carries out a change, or records why it could not be.
    ///
    /// - Returns: The settings to save, or `nil` when nothing changed. A refusal leaves
    ///   ``settings`` exactly as it was, so a caller that ignores the answer is left
    ///   holding the state that was already good.
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
        // The field follows the setting however the change arrived, so a shortcut
        // altered from anywhere else cannot leave the window showing the old one.
        if recorder.binding != settings.hotkey {
            recorder = SettingsShortcutRecorder(binding: settings.hotkey)
        }
        return settings
    }

    /// Takes a keystroke aimed at the shortcut field and applies whatever it earned.
    ///
    /// - Parameters:
    ///   - keyCode: The hardware key code of the key that went down.
    ///   - modifiers: The modifiers held with it.
    /// - Returns: The settings to save, or `nil` when the keystroke changed nothing.
    @discardableResult
    public mutating func record(
        keyCode: UInt16, modifiers: Set<HotkeyModifier>
    ) -> Settings? {
        switch recorder.record(keyCode: keyCode, modifiers: modifiers) {
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

    // MARK: - Forgetting

    /// Asks for something to be removed.
    ///
    /// - Parameter removal: The button the user pressed, and what it stands for.
    /// - Returns: The reset to carry out now, or `nil` — either because it has to be
    ///   confirmed first, in which case ``pendingRemoval`` is now the question to put
    ///   in front of the user, or because it was refused, in which case ``rejection``
    ///   says why. Nothing has been removed either way.
    @discardableResult
    public mutating func request(_ removal: SettingsRemoval) -> SettingsReset? {
        // The same gate the row was drawn from, asked again here: a button that was
        // greyed out cannot be pressed, but a button that became stale while the window
        // sat open can, and this is where that is caught.
        if let reason = SettingsEditor.unavailability(of: removal.reset, given: personalisation) {
            rejection = reason
            return nil
        }
        rejection = nil
        // Both: ``SettingsReset/isConfirmed`` is the rule, the row only carries the wording.
        guard removal.confirmation == nil, !removal.reset.isConfirmed else {
            pendingRemoval = removal
            return nil
        }
        return removal.reset
    }

    /// The user said yes.
    ///
    /// Takes the removal the question was drawn with rather than reading
    /// ``pendingRemoval`` back. A dialogue clears itself as it closes, and whether that
    /// happens before or after the button's own action is the window server's business:
    /// an answer that depended on the order would work by luck, and the failure would be
    /// a reset the user asked for and did not get.
    ///
    /// - Parameter removal: The button the question was showing.
    /// - Returns: The reset to carry out, or `nil` for a removal that was never a
    ///   question in the first place, which cannot have been answered.
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

    /// A reset has been carried out; these are the counts that are left.
    ///
    /// The preferences half of a reset is settled here rather than in the store,
    /// because ``Settings`` is the one thing on this screen no store owns — the window
    /// holds it and hands it back to be saved, exactly as it does for every other change.
    ///
    /// - Parameters:
    ///   - reset: The level that was carried out.
    ///   - personalisation: What the stores hold now, read back rather than deduced, so
    ///     the counts beside the buttons cannot drift from the files.
    /// - Returns: The settings to save, when the reset put them back to their defaults.
    @discardableResult
    public mutating func completed(
        _ reset: SettingsReset, leaving personalisation: SettingsPersonalisation
    ) -> Settings? {
        self.personalisation = personalisation
        pendingRemoval = nil
        rejection = nil
        guard reset.targets.contains(.preferences) else { return nil }
        settings = .default
        // The field follows the setting, as it does after any other change: a reset
        // that left the old shortcut on screen would be showing one that no longer works.
        recorder = SettingsShortcutRecorder(binding: settings.hotkey)
        return settings
    }

    /// A reset was asked for and could not be finished.
    ///
    /// Said out loud rather than swallowed. The one thing a user cannot be left to
    /// assume is whether the words they asked to delete are still there.
    public mutating func failed(_ reset: SettingsReset) {
        pendingRemoval = nil
        rejection = SettingsEditor.reason(forFailed: reset)
    }

    // MARK: - The shortcut field

    public mutating func beginRecordingShortcut() {
        rejection = nil
        recorder.beginRecording()
    }

    public mutating func cancelRecordingShortcut() {
        rejection = nil
        recorder.cancel()
    }
}
