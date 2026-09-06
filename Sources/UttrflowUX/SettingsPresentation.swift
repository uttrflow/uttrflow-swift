// The shape of the Settings window: panes, cards, rows, controls, and the changes they ask for.
public import UttrflowCore
public import UttrflowPredict
public import UttrflowSettings

// MARK: - What a screen is made of

/// One entry in the sidebar, built from ``SettingsTab/allCases`` so no tab can go missing.
public struct SettingsTabItem: Sendable, Equatable, Identifiable {
    public let tab: SettingsTab
    public let title: String
    public let symbolName: String

    public var id: SettingsTab { tab }
}

/// A whole screen: cards, and at most a statement above them and a note below.
public struct SettingsPane: Sendable, Equatable {
    public let tab: SettingsTab
    public let title: String
    /// The statement at the top of the pane, when the tab opens with one.
    public let banner: SettingsBanner?
    public let groups: [SettingsGroup]
    /// The tinted note at the foot of the pane, when there is one.
    public let callout: SettingsCallout?
}

/// A card, and the small heading above it when it needs one.
public struct SettingsGroup: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let rows: [SettingsRow]
}

/// A line in a card: what it offers, and whether it can be operated.
public struct SettingsRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// The quieter second line, when the label alone would not be enough.
    public let explanation: String?
    public let control: SettingsControl
    /// Why this row cannot be operated, said in words the user can act on.
    public let unavailability: String?

    public var isEnabled: Bool { unavailability == nil }

    /// What VoiceOver reads, including why the row is off, which grey alone does not say.
    public var accessibilityLabel: String {
        [label, explanation, unavailability].compactMap(\.self).joined(separator: ". ")
    }

    /// Builds a row; operable unless given a reason it is not.
    public init(
        id: String,
        label: String,
        explanation: String? = nil,
        control: SettingsControl,
        unavailability: String? = nil
    ) {
        self.id = id
        self.label = label
        self.explanation = explanation
        self.control = control
        self.unavailability = unavailability
    }
}

/// The statement a tab can open with — the privacy promise, and nothing else so far.
public struct SettingsBanner: Sendable, Equatable {
    public let symbolName: String
    public let title: String
    public let message: String
}

/// The tinted note at the foot of a pane: context, never an instruction.
public struct SettingsCallout: Sendable, Equatable {
    public let symbolName: String
    public let message: String
}

// MARK: - Controls

/// The thing on the right-hand side of a row, as a closed set the view draws every case of.
public enum SettingsControl: Sendable, Equatable {
    /// A switch.
    case toggle(field: SettingsToggleField, isOn: Bool)

    /// Mutually exclusive choices shown side by side.
    case segmented(options: [SettingsOption], selectedID: String)

    /// Mutually exclusive choices behind a pop-up, for lists too long to lay out flat.
    case menu(options: [SettingsOption], selectedID: String)

    /// The four screen corners the floating button can park in.
    case anchorPicker(selected: DockAnchor)

    /// The shortcut in force, as the keycaps it is drawn on.
    case shortcut(keys: [String])

    /// A tick in a list where more than one line can be ticked at once.
    case tick(isTicked: Bool, change: SettingsChange)

    /// A button that removes something, which the view draws destructively without being told to.
    case removal(SettingsRemoval)

    /// A button that does something and destroys nothing, so it earns neither red nor a question.
    case action(title: String, change: SettingsChange)

    /// A switch for a row that stands for one application rather than one named field.
    case applicationSwitch(isOn: Bool, change: SettingsChange)

    /// A value with nothing to press — a version number, a count, a date.
    case text(String)
}

/// A destructive button: what it says, what it removes, and what it asks first.
public struct SettingsRemoval: Sendable, Equatable {
    public let reset: SettingsReset
    /// What the button says, ending in an ellipsis exactly when pressing it asks first.
    public let title: String
    /// What the user is shown before anything goes, or `nil` when a recoverable act needs no asking.
    public let confirmation: SettingsConfirmation?

    /// Builds a destructive button; a `nil` confirmation means it acts without asking.
    public init(reset: SettingsReset, title: String, confirmation: SettingsConfirmation?) {
        self.reset = reset
        self.title = title
        self.confirmation = confirmation
    }
}

/// The question asked before something irreversible happens.
public struct SettingsConfirmation: Sendable, Equatable {
    public let title: String
    /// What will be removed, counted, so the user decides on a number rather than on a guess.
    public let message: String
    public let confirmTitle: String
    public let cancelTitle: String

    /// The button Return presses, always the one that removes nothing.
    public var defaultTitle: String { cancelTitle }

    /// Builds the question; Return presses the cancel button whatever it is called.
    public init(title: String, message: String, confirmTitle: String, cancelTitle: String) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
    }
}

/// One choice in a segmented control or a pop-up, carrying the change picking it means.
public struct SettingsOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let change: SettingsChange
}

// MARK: - Changes

/// A switch the user can throw, named so a row and a change cannot disagree about the field.
public enum SettingsToggleField: String, Sendable, Equatable, CaseIterable {
    case showsFloatingButton
    case shrinksToGripWhenIdle
    case minimisesWhileDictating
    case playsSoundWhenRecordingStarts
    case opensAtLogin
    case installsUpdatesAutomatically
    case suggestionsEnabled
    case quietSuggestions
}

/// Everything the user can ask for on this screen; only ``SettingsEditor`` decides what happens.
public enum SettingsChange: Sendable, Equatable {
    case toggle(SettingsToggleField, isOn: Bool)
    case activation(HotkeyActivation)
    case anchor(DockAnchor)
    case shortcut(HotkeyBinding)
    case tidying(SettingsTidyingLevel)
    case transcription(SettingsTranscriptionQuality)
    case spokenLanguage(LanguageCode, isSpoken: Bool)
    case retention(days: Int)
    case appearance(AppAppearance)

    /// Switch one clean-up step on or off; a step nobody offers is refused.
    case cleaningStep(PassID, isOn: Bool)

    /// Treat one app as a kind of place, whatever the table says it is.
    case appDestination(
        bundleIdentifier: String, name: String?, destination: UttrflowCore.Destination)

    /// Put one app back on the table's answer.
    case forgetAppDestination(bundleIdentifier: String)

    /// Switches suggestions on or off in one application, the only way out of the shipped deny list.
    case suggestionsHere(application: String, isOn: Bool)

    /// Chooses the key that takes a suggestion in one application.
    case suggestionAcceptKey(application: String, key: AcceptKey)

    /// Starts the half-hour pause everywhere, or lifts one that is still running.
    case pauseSuggestions(isOn: Bool)

    /// Asks the update feed now rather than waiting for the next scheduled check.
    case checkForUpdatesNow
}
