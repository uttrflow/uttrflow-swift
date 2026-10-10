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
        case .shortcut(let action, let binding):
            if let rejection = rejection(forShortcut: binding, for: action) { throw rejection }
            if let clash = clash(for: action, binding: binding, in: updated) { throw clash }
            updated.shortcuts.replace(at: 0, with: binding, for: action)
            updated.shortcutsReturnedToDefault.remove(action)
        case .tidying(let level):
            try applyTidying(level, to: &updated, given: capabilities)
        case .spokenLanguage(let code, let isSpoken):
            try applyLanguage(code, isSpoken: isSpoken, to: &updated)
        case .pauses(let pauses):
            updated.profile.pauses = pauses
        case .appearance(let appearance):
            // No capability to check: every Mac can draw itself light or dark.
            updated.appearance = appearance
        case .contextLevel(let level):
            // No capability to check: reading less never needs a permission.
            updated.contextLevel = level
        case .microphone(let uid):
            // An absent device is kept: capture falls back to the default until it is plugged in again.
            updated.microphoneUID = uid
        case .handsFreeDoubleTap(let milliseconds):
            guard Settings.handsFreeDoubleTapChoices.contains(milliseconds) else {
                throw SettingsRejection(reason: "Choose a listed hands-free interval.")
            }
            updated.handsFreeDoubleTapMilliseconds = milliseconds
        case .handsFreeHold(let milliseconds):
            guard Settings.handsFreeHoldChoices.contains(milliseconds) else {
                throw SettingsRejection(reason: "Choose a listed hold length.")
            }
            updated.handsFreeHoldMilliseconds = milliseconds
        case .endOnSilence(let seconds):
            guard seconds == 0 || SilenceStop(seconds: seconds) != nil else {
                throw SettingsRejection(reason: "Choose a listed wait.")
            }
            updated.endOnSilenceSeconds = seconds
        case .retention(let days):
            try applyRetention(days: days, to: &updated)
        case .cleaningStep(let step, let isOn):
            try applyCleaningStep(step, isOn: isOn, to: &updated)
        case .appDestination(let bundle, let name, let destination):
            try applyDestination(destination, for: bundle, named: name, to: &updated)
        case .forgetAppDestination(let bundle):
            updated.destinations = updated.destinations.removing(bundle)
        case .suggestionsHere(let application, let isOn):
            try requireSuggestionsAreOn(in: settings)
            if isOn {
                updated.suggestions.removePreferences(for: application)
            } else {
                updated.suggestions.set(application, isOn: false)
            }
        case .suggestionAcceptKey(let application, let key):
            try requireSuggestionsAreOn(in: settings)
            updated.suggestions.setAcceptKey(key, in: application)
        case .pauseSuggestions(let isOn):
            try requireSuggestionsAreOn(in: settings)
            updated.suggestions.setPaused(isOn, at: moment)
        case .checkForUpdatesNow, .chooseApplicationToTurnOffSuggestions, .chooseApplicationForDestination,
            .retrySuggestionModel, .exportPersonalData, .importPersonalData, .manageClipboardExclusions,
            .pauseClipboardCapture, .openSystemSettings, .openPage:
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
        case .dictationEnabled: settings.dictationEnabled = isOn
        case .handsFreeEnabled: settings.handsFreeEnabled = isOn
        case .clipboardEnabled: settings.clipboardEnabled = isOn
        case .showsFloatingButton: settings.showsFloatingButton = isOn
        case .shrinksToGripWhenIdle: settings.shrinksToGripWhenIdle = isOn
        case .minimisesWhileDictating: settings.minimisesWhileDictating = isOn
        case .playsSoundWhenRecordingStarts: settings.playsSoundWhenRecordingStarts = isOn
        case .opensAtLogin: settings.opensAtLogin = isOn
        case .checksForUpdatesAutomatically: settings.checksForUpdatesAutomatically = isOn
        case .installsUpdatesAutomatically: settings.installsUpdatesAutomatically = isOn
        case .sharesUsageStatistics: settings.sharesUsageStatistics = isOn
        case .sendsCrashReports: settings.sendsCrashReports = isOn
        case .suggestionsEnabled: settings.suggestions.isEnabled = isOn
        case .quietSuggestions: settings.suggestions.isQuiet = isOn
        case .learnsFromDictation: settings.learnsFromDictation = isOn
        }
    }

    /// The one sentence every suggestion control that depends on the master switch is refused with.
    static let suggestionsAreOff = "Turn AI suggestions on before choosing how they behave."

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
        case .dictationEnabled, .handsFreeEnabled, .clipboardEnabled, .showsFloatingButton,
            .minimisesWhileDictating, .sharesUsageStatistics:
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
        case .checksForUpdatesAutomatically:
            capabilities.canCheckForUpdates
                ? nil
                : "This build has no update feed, so there is nothing to check."
        case .suggestionsEnabled, .sendsCrashReports, .learnsFromDictation:
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

    /// Refuses a shortcut another one already holds, naming it so the user knows what to change.
    static func clash(
        for action: ShortcutAction, binding: HotkeyBinding, in settings: Settings
    ) -> SettingsRejection? {
        guard let other = settings.shortcuts.action(holding: binding, besides: action) else {
            return nil
        }
        return SettingsRejection(
            reason: "That is already the \(ShortcutRegistry.label(for: other).lowercased()) shortcut.")
    }

    /// Said for ⌘, ⌥, ⌃ or ⇧ alone, naming Fn because it is the one key that can be held by itself.
    static let bareModifier =
        "That key alone is part of too many other shortcuts. Add a key or another modifier, or hold fn after setting ‘Press 🌐 key to’ to Do Nothing in System Settings → Keyboard."

    /// Said for a held-modifier chord on an action Carbon registers, which cannot arm it. See `Docs/core-hotkeys.md`.
    static let heldChordNotClaimable =
        "A held combination of modifiers can only be the Dictate shortcut. Add a letter or number key."

    /// Said for F13 to F20 alone on an action Carbon registers, which never fires a hot key without a modifier.
    static let bareKeyNotClaimable =
        "A key on its own can only be the Dictate shortcut. Hold ⌘, ⌥, ⌃ or ⇧ as well."

    /// The one gate a shortcut passes to be saved, asked by both the recorder and the editor.
    static func rejection(
        forShortcut binding: HotkeyBinding, for action: ShortcutAction
    ) -> SettingsRejection? {
        if binding.isBareModifier {
            return SettingsRejection(reason: bareModifier)
        }
        if !binding.isUsable {
            return SettingsRejection(
                reason: "Hold ⌘, ⌥, ⌃ or ⇧ as well, or the shortcut would fire while you type.")
        }
        if !binding.isCoherent {
            return SettingsRejection(
                reason: "That combination did not register cleanly. Press and hold it again.")
        }
        if !binding.isDeliverable {
            // Reached only by a key code no keyboard sends; modifier-only combinations are fine.
            return SettingsRejection(
                reason: "That key did not come from the keyboard, so it cannot start a dictation.")
        }
        if binding.heldModifier != nil,
            ShortcutRegistry.descriptor(for: action).delivery == .claimed
        {
            // Deliverable in general, but Carbon refuses every held-modifier-only combination.
            return SettingsRejection(reason: heldChordNotClaimable)
        }
        if binding.modifiers.isEmpty, binding.heldModifier == nil,
            ShortcutRegistry.descriptor(for: action).delivery == .claimed
        {
            // Only the watched Dictate shortcut takes a key that types nothing on its own; Carbon needs a modifier.
            return SettingsRejection(reason: bareKeyNotClaimable)
        }
        if action == .dictate, binding.heldModifier == nil,
            let reason = dictateCombinationConflict(binding)
        {
            return SettingsRejection(reason: reason)
        }
        return nil
    }

    /// Refuses Dictate key combinations that type into the focused app or invoke macOS actions.
    private static func dictateCombinationConflict(_ binding: HotkeyBinding) -> String? {
        // Option types a character only alone or with Shift; Control or Command turns it into a shortcut.
        if binding.modifiers.contains(.option), binding.modifiers.isSubset(of: [.option, .shift]),
            printableKeyCodes.contains(binding.keyCode)
        {
            return
                "Option with a character key can type into the app you are using. Choose another Dictate shortcut."
        }
        if binding.keyCode == 49, binding.modifiers.contains(.command) {
            return
                "⌘Space opens Spotlight, so it can take focus from the app you are dictating into. Choose another Dictate shortcut."
        }
        if binding.keyCode == 49, binding.modifiers.contains(.control) {
            return
                "⌃Space changes the input source, so it can interrupt dictation. Choose another Dictate shortcut."
        }
        if binding.keyCode == 48, binding.modifiers.contains(.command) {
            return
                "⌘Tab switches apps, so it can take focus from the app you are dictating into. Choose another Dictate shortcut."
        }
        return nil
    }

    /// ANSI key codes whose key can type a character with Option held.
    private static let printableKeyCodes: Set<UInt16> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
        37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 49, 50,
    ]

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
        if case .unavailable(let reason) = capabilities.foundationModelAvailability {
            return reason.diagnosticDescription + ". Uttrflow will still apply its rules."
        }
        return "Full tidying is not available on this Mac yet, so Uttrflow will still apply its rules."
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

    // MARK: - Clean-up steps

    /// Switches one step on or off, refusing rather than ignoring a step that is the formatter's.
    private static func applyCleaningStep(
        _ step: PassID, isOn: Bool, to settings: inout Settings
    ) throws(SettingsRejection) {
        guard CleaningSteps.isOffered(step) else {
            throw SettingsRejection(
                reason: "That part of the clean-up follows the app you are typing into.")
        }
        settings.cleaning = settings.cleaning.setting(step, isOn: isOn)
    }

    // MARK: - Where the words go

    /// Treats one app as a kind of place, refusing an override with no app to be about.
    private static func applyDestination(
        _ destination: UttrflowCore.Destination,
        for bundleIdentifier: String,
        named name: String?,
        to settings: inout Settings
    ) throws(SettingsRejection) {
        guard !bundleIdentifier.isEmpty else {
            throw SettingsRejection(
                reason: "Uttrflow could not tell which app that was, so it cannot remember this.")
        }
        settings.destinations = settings.destinations.setting(
            destination, for: bundleIdentifier, named: name)
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
        case .persona:
            personalisation.persona.isEmpty ? "Uttrflow has not noticed anything about you yet." : nil
        case .personaFact(let fact):
            personalisation.persona.contains { $0.fact == fact } ? nil : "This has already been removed."
        }
    }

    /// Why a reset waits, said while a dictation could still write into what it removes.
    static let finishTheDictationFirst =
        "A dictation is still under way. Let it finish, then try again."

    /// What to say when the disk refused a reset, naming what is still here rather than apologising.
    static func reason(forFailed reset: SettingsReset) -> String {
        switch reset {
        case .learnedWords, .suggestions, .persona, .personaFact:
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
