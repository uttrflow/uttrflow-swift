import UttrflowCore
public import UttrflowSettings

/// Why a change was refused, in the words the user is shown.
///
/// Carries the sentence rather than a code, because there is exactly one audience for
/// a refusal on a settings screen and it is the person who just tried. A caller that
/// wanted to branch on the kind of refusal would be making a decision this module has
/// already made.
public struct SettingsRejection: Error, Sendable, Equatable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

/// The only thing that changes ``Settings``.
///
/// Pure, and the single authority on what a change means. Two rules it enforces rather
/// than trusts: a shortcut macOS would never deliver is never saved, and the clean-up
/// preference always ends in a kind that can handle anything. Both are failures the
/// user could not recover from afterwards — a shortcut that does nothing leaves them
/// with no way to dictate and no way back to this screen, and a preference the pipeline
/// runs off the end of loses the words it was given.
public enum SettingsEditor {
    /// Applies a change, or refuses it and leaves the settings exactly as they were.
    ///
    /// - Parameters:
    ///   - change: What the user asked for.
    ///   - settings: What they have now.
    ///   - capabilities: What this Mac can do.
    /// - Returns: The settings to save.
    /// - Throws: ``SettingsRejection`` when the change cannot be honoured, carrying the
    ///   sentence to put in front of the user. The settings passed in are untouched, so
    ///   a caller that ignores the throw still holds the state that was already good.
    public static func apply(
        _ change: SettingsChange,
        to settings: Settings,
        given capabilities: SettingsCapabilities = .everything
    ) throws(SettingsRejection) -> Settings {
        var updated = settings
        switch change {
        case .toggle(let field, let isOn):
            try applyToggle(field, isOn: isOn, to: &updated, given: capabilities)
        case .activation(let activation):
            updated.hotkeyActivation = activation
        case .anchor(let anchor):
            updated.floatingButtonAnchor = anchor
        case .shortcut(let binding):
            if let rejection = rejection(forShortcut: binding) { throw rejection }
            updated.hotkey = binding
        case .tidying(let level):
            try applyTidying(level, to: &updated, given: capabilities)
        case .transcription(let quality):
            try applyTranscription(quality, to: &updated, given: capabilities)
        case .spokenLanguage(let code, let isSpoken):
            try applyLanguage(code, isSpoken: isSpoken, to: &updated)
        case .appearance(let appearance):
            // No capability to check: drawing itself light or dark is something every Mac
            // can do, and refusing it would be refusing a preference for no reason.
            updated.appearance = appearance
        case .retention(let days):
            try applyRetention(days: days, to: &updated)
        }
        return updated
    }

    // MARK: - Toggles

    private static func applyToggle(
        _ field: SettingsToggleField,
        isOn: Bool,
        to settings: inout Settings,
        given capabilities: SettingsCapabilities
    ) throws(SettingsRejection) {
        // Turning something off never needs a capability: whatever is missing, off is
        // a state the machine can certainly manage.
        if isOn, let reason = unavailability(of: field, given: capabilities, in: settings) {
            throw SettingsRejection(reason: reason)
        }
        switch field {
        case .showsFloatingButton: settings.showsFloatingButton = isOn
        case .shrinksToGripWhenIdle: settings.shrinksToGripWhenIdle = isOn
        case .minimisesWhileDictating: settings.minimisesWhileDictating = isOn
        case .playsSoundWhenRecordingStarts: settings.playsSoundWhenRecordingStarts = isOn
        case .opensAtLogin: settings.opensAtLogin = isOn
        }
    }

    /// Why a switch cannot be turned on, or `nil` when it can.
    ///
    /// Shared by the row and by ``apply(_:to:given:)`` so that a switch drawn as
    /// operable and a change accepted as valid can never come apart: the row shows this
    /// sentence, and the editor throws the same one if the change arrives anyway.
    static func unavailability(
        of field: SettingsToggleField,
        given capabilities: SettingsCapabilities,
        in settings: Settings
    ) -> String? {
        switch field {
        case .showsFloatingButton, .minimisesWhileDictating:
            nil
        case .shrinksToGripWhenIdle:
            settings.showsFloatingButton
                ? nil : "Turn the floating button on before choosing how it behaves."
        case .playsSoundWhenRecordingStarts:
            capabilities.canPlayRecordingSound
                ? nil
                : "This Mac has no audio output, so there is nothing to play the sound through."
        case .opensAtLogin:
            reasonLoginIsUnavailable(capabilities.launchAtLogin)
        }
    }

    private static func reasonLoginIsUnavailable(_ status: LaunchAtLoginStatus) -> String? {
        switch status {
        case .enabled, .disabled:
            nil
        case .requiresApproval:
            "macOS is waiting for you to allow Uttrflow under Login Items in System Settings."
        case .unavailable:
            "This copy of Uttrflow is not installed as an app, so macOS has no login item for it."
        }
    }

    // MARK: - Shortcut

    /// Whether a recorded combination can be saved, and why not when it cannot.
    ///
    /// Deliberately the only gate: the recorder asks this before it commits and the
    /// editor asks it again before it writes, so there is no path — a stored value from
    /// another build included — by which an undeliverable shortcut becomes the one the
    /// user is left with.
    ///
    /// The three sentences come from ``HotkeyBinding/isUsable`` and
    /// ``HotkeyBinding/isDeliverable``, which are the whole of what this module can
    /// know. Naming the offending key code would mean holding a copy of the platform's
    /// key tables here, and two copies of a table is how they come to disagree.
    static func rejection(forShortcut binding: HotkeyBinding) -> SettingsRejection? {
        if !binding.isUsable {
            return SettingsRejection(
                reason: "Hold ⌘, ⌥, ⌃ or ⇧ as well, or the shortcut would fire while you type.")
        }
        if !binding.isDeliverable {
            // Reached only by a key code no keyboard sends. The old wording here —
            // "Try a letter, a number or Space" — was written when modifier-only
            // combinations were refused too, and it described the wrong problem to
            // everybody who pressed ⌃⌥: it implied they had pressed something exotic when
            // they had pressed something perfectly ordinary that this app declined to
            // support. Those are allowed now, and this sentence is back to covering only
            // what it can actually mean.
            return SettingsRejection(
                reason: "That key did not come from the keyboard, so it cannot start a dictation.")
        }
        return nil
    }

    // MARK: - Engines

    private static func applyTidying(
        _ level: SettingsTidyingLevel,
        to settings: inout Settings,
        given capabilities: SettingsCapabilities
    ) throws(SettingsRejection) {
        if let reason = unavailability(ofTidying: level, given: capabilities) {
            throw SettingsRejection(reason: reason)
        }
        // Through `normalised` rather than assigned: the level already yields a lawful
        // order, and running it through the one gate anyway means no second path to
        // this field exists for a later change to forget about.
        settings.engines.transformerPreference = SettingsEngines.normalised(level.preference)
    }

    static func unavailability(
        ofTidying level: SettingsTidyingLevel,
        given capabilities: SettingsCapabilities
    ) -> String? {
        guard level == .standard, !capabilities.canTidyBeyondTheFloor else { return nil }
        return "Full tidying is not available on this Mac yet, so Uttrflow will punctuate only."
    }

    private static func applyTranscription(
        _ quality: SettingsTranscriptionQuality,
        to settings: inout Settings,
        given capabilities: SettingsCapabilities
    ) throws(SettingsRejection) {
        if let reason = unavailability(ofTranscription: quality, given: capabilities) {
            throw SettingsRejection(reason: reason)
        }
        settings.engines.speech = quality.engine
    }

    static func unavailability(
        ofTranscription quality: SettingsTranscriptionQuality,
        given capabilities: SettingsCapabilities
    ) -> String? {
        capabilities.readySpeechEngines.contains(quality.engine)
            ? nil : "This option needs a download that has not finished yet."
    }

    // MARK: - Languages

    private static func applyLanguage(
        _ code: LanguageCode,
        isSpoken: Bool,
        to settings: inout Settings
    ) throws(SettingsRejection) {
        var languages = settings.profile.preferredLanguages
        if isSpoken {
            guard !languages.contains(code) else { return }
            // Appended rather than inserted: the order is the order the user added
            // them, which is as good a guess at their first language as this screen has.
            languages.append(code)
        } else {
            guard languages.count > 1 else {
                throw SettingsRejection(
                    reason: "Uttrflow needs at least one language to listen for.")
            }
            languages.removeAll { $0 == code }
        }
        settings.profile.preferredLanguages = languages
    }

    // MARK: - Forgetting

    /// Why a reset cannot be asked for, or `nil` when it can.
    ///
    /// The same idiom as every other row on this screen: the row shows this sentence and
    /// ``SettingsSession/request(_:)`` refuses on the same one, so a button drawn as
    /// operable cannot then decline to do anything.
    static func unavailability(
        of reset: SettingsReset, given personalisation: SettingsPersonalisation
    ) -> String? {
        switch reset {
        case .learnedWords:
            personalisation.learnedWords > 0
                ? nil : "Uttrflow has not picked up any words of its own yet."
        case .everything:
            // Always available. Even with nothing saved there are preferences to put
            // back, so there is no state in which pressing it achieves nothing — and a
            // greyed reset is a dead end for the one user who most wants one.
            nil
        }
    }

    /// What to say when a reset was asked for and the disk refused.
    ///
    /// Says what is still here rather than apologising. A user who asked for their words
    /// to be deleted and is told "something went wrong" does not know whether they were,
    /// which is the one thing they needed to find out.
    static func reason(forFailed reset: SettingsReset) -> String {
        switch reset {
        case .learnedWords:
            "Uttrflow could not write to the disk, so nothing was forgotten. Try again."
        case .everything:
            "Uttrflow could not write to the disk, so some of this may still be here. Try again."
        }
    }

    // MARK: - Retention

    private static func applyRetention(
        days: Int,
        to settings: inout Settings
    ) throws(SettingsRejection) {
        guard SettingsRetention.offeredDays.contains(days) else {
            throw SettingsRejection(
                reason: "Choose one of the periods offered; anything else is not kept.")
        }
        settings.transcriptRetentionDays = days
    }
}
