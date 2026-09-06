// The only thing that changes `Settings`, and the sentences it refuses a change with.
public import struct Foundation.Date
import UttrflowCore
import UttrflowPredict
public import UttrflowSettings

/// Why a change was refused, carried as the sentence the user is shown rather than a code.
public struct SettingsRejection: Error, Sendable, Equatable {
    public let reason: String

    /// Wraps the sentence to show.
    public init(reason: String) {
        self.reason = reason
    }
}

/// The only thing that changes ``Settings``, and the single authority on what a change means.
public enum SettingsEditor {
    /// Applies a change, or throws the sentence refusing it and leaves the settings untouched.
    public static func apply(
        _ change: SettingsChange,
        to settings: Settings,
        given capabilities: SettingsCapabilities = .everything,
        at moment: Date = Date()
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
            // No capability to check: every Mac can draw itself light or dark.
            updated.appearance = appearance
        case .retention(let days):
            try applyRetention(days: days, to: &updated)
        case .suggestionsHere(let application, let isOn):
            try requireSuggestionsAreOn(in: settings)
            updated.suggestions.set(application, isOn: isOn)
        case .suggestionAcceptKey(let application, let key):
            try requireSuggestionsAreOn(in: settings)
            updated.suggestions.setAcceptKey(key, in: application)
        case .pauseSuggestions(let isOn):
            try requireSuggestionsAreOn(in: settings)
            updated.suggestions.setPaused(isOn, at: moment)
        case .checkForUpdatesNow:
            // Named rather than left to a `default`, which would swallow the next case added.
            break
        }
        return updated
    }

    // MARK: - Toggles

    /// Throws a capability's refusal, then writes the switch.
    private static func applyToggle(
        _ field: SettingsToggleField,
        isOn: Bool,
        to settings: inout Settings,
        given capabilities: SettingsCapabilities
    ) throws(SettingsRejection) {
        // Turning something off needs no capability; off is a state any Mac can manage.
        if isOn, let reason = unavailability(of: field, given: capabilities, in: settings) {
            throw SettingsRejection(reason: reason)
        }
        switch field {
        case .showsFloatingButton: settings.showsFloatingButton = isOn
        case .shrinksToGripWhenIdle: settings.shrinksToGripWhenIdle = isOn
        case .minimisesWhileDictating: settings.minimisesWhileDictating = isOn
        case .playsSoundWhenRecordingStarts: settings.playsSoundWhenRecordingStarts = isOn
        case .opensAtLogin: settings.opensAtLogin = isOn
        case .installsUpdatesAutomatically: settings.installsUpdatesAutomatically = isOn
        case .suggestionsEnabled: settings.suggestions.isEnabled = isOn
        case .quietSuggestions: settings.suggestions.isQuiet = isOn
        }
    }

    /// The one sentence every suggestion control that depends on the master switch is refused with.
    static let suggestionsAreOff = "Turn suggestions on before choosing how they behave."

    /// Refuses a suggestion control while the feature is off, so no change is accepted unacted on.
    private static func requireSuggestionsAreOn(in settings: Settings) throws(SettingsRejection) {
        guard !settings.suggestions.isEnabled else { return }
        throw SettingsRejection(reason: suggestionsAreOff)
    }

    /// Why a switch cannot be turned on, shared by the row and by ``apply(_:to:given:)``.
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
        case .installsUpdatesAutomatically:
            capabilities.canCheckForUpdates
                ? nil
                : "This build has no update feed, so there is nothing for it to install."
        case .suggestionsEnabled:
            nil
        case .quietSuggestions:
            settings.suggestions.isEnabled ? nil : suggestionsAreOff
        }
    }

    /// Why macOS will not open Uttrflow at login, or `nil` when it will.
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

    /// The one gate a shortcut passes to be saved, asked by both the recorder and the editor.
    static func rejection(forShortcut binding: HotkeyBinding) -> SettingsRejection? {
        if !binding.isUsable {
            return SettingsRejection(
                reason: "Hold ⌘, ⌥, ⌃ or ⇧ as well, or the shortcut would fire while you type.")
        }
        if !binding.isDeliverable {
            // Reached only by a key code no keyboard sends; modifier-only combinations are fine.
            return SettingsRejection(
                reason: "That key did not come from the keyboard, so it cannot start a dictation.")
        }
        return nil
    }

    // MARK: - Engines

    /// Throws when the Mac cannot tidy this far, then normalises the level into a preference.
    private static func applyTidying(
        _ level: SettingsTidyingLevel,
        to settings: inout Settings,
        given capabilities: SettingsCapabilities
    ) throws(SettingsRejection) {
        if let reason = unavailability(ofTidying: level, given: capabilities) {
            throw SettingsRejection(reason: reason)
        }
        // Through `normalised` even so, to leave no second path to this field.
        settings.engines.transformerPreference = SettingsEngines.normalised(level.preference)
    }

    /// Why this much tidying is not on offer, or `nil` when it is.
    static func unavailability(
        ofTidying level: SettingsTidyingLevel,
        given capabilities: SettingsCapabilities
    ) -> String? {
        guard level == .standard, !capabilities.canTidyBeyondTheFloor else { return nil }
        return "Full tidying is not available on this Mac yet, so Uttrflow will punctuate only."
    }

    /// Throws when the engine behind this quality is not downloaded, then selects it.
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

    /// Why this quality cannot be chosen, or `nil` when it can.
    static func unavailability(
        ofTranscription quality: SettingsTranscriptionQuality,
        given capabilities: SettingsCapabilities
    ) -> String? {
        capabilities.readySpeechEngines.contains(quality.engine)
            ? nil : "This option needs a download that has not finished yet."
    }

    // MARK: - Languages

    /// Adds or removes a spoken language, refusing to leave the profile with none.
    private static func applyLanguage(
        _ code: LanguageCode,
        isSpoken: Bool,
        to settings: inout Settings
    ) throws(SettingsRejection) {
        var languages = settings.profile.preferredLanguages
        if isSpoken {
            guard !languages.contains(code) else { return }
            // Appended, so the order is the order they were added, the best guess this screen has.
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

    /// Why a reset cannot be asked for, shared by the row and by ``SettingsSession/request(_:)``.
    static func unavailability(
        of reset: SettingsReset, given personalisation: SettingsPersonalisation
    ) -> String? {
        switch reset {
        case .learnedWords:
            personalisation.learnedWords > 0
                ? nil : "Uttrflow has not picked up any words of its own yet."
        case .everything:
            // Always available: there are always preferences to put back.
            nil
        case .suggestions(let application):
            personalisation.suggestions(from: application) > 0
                ? nil
                : "Uttrflow has not picked up anything in \(SuggestionApplications.name(of: application)) yet."
        }
    }

    /// What to say when the disk refused a reset, naming what is still here rather than apologising.
    static func reason(forFailed reset: SettingsReset) -> String {
        switch reset {
        case .learnedWords, .suggestions:
            "Uttrflow could not write to the disk, so nothing was forgotten. Try again."
        case .everything:
            "Uttrflow could not write to the disk, so some of this may still be here. Try again."
        }
    }

    // MARK: - Retention

    /// Writes a retention period, refusing any the store would not round-trip.
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
