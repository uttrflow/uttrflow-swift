// The shape of the Settings page: panes, cards, rows, controls, and the changes they ask for.
public import UttrflowCore
public import UttrflowPredict
public import UttrflowSettings

// MARK: - What a screen is made of

/// One entry in the sidebar, built from ``SettingsTab/allCases`` so no tab can go missing.
public struct SettingsTabItem: Sendable, Equatable, Identifiable {
    public let tab: SettingsTab
    public let title: String
    public let symbolName: String
    public let badge: String?

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
    /// The worked tidying example, drawn under the group whose id it names.
    public let example: SettingsTidyExample?
    /// What an empty search says, set only on a search that matched nothing.
    public let emptySearch: String?
    /// Why most of the pane cannot be operated, said once above the cards instead of on every row.
    public let unavailability: String?

    /// Builds a pane; no example and no empty search unless given them.
    public init(
        tab: SettingsTab,
        title: String,
        banner: SettingsBanner?,
        groups: [SettingsGroup],
        callout: SettingsCallout?,
        example: SettingsTidyExample? = nil,
        emptySearch: String? = nil,
        unavailability: String? = nil
    ) {
        self.tab = tab
        self.title = title
        self.banner = banner
        self.groups = groups
        self.callout = callout
        self.example = example
        self.emptySearch = emptySearch
        self.unavailability = unavailability
    }
}

/// The same sentence as spoken and as written at the level in force, so the choice is shown.
public struct SettingsTidyExample: Sendable, Equatable {
    /// The group the example is drawn under.
    public let groupID: String
    /// The sentence as spoken.
    public let spoken: String
    /// The label over the written sentence, naming the level.
    public let writtenLabel: String
    /// The sentence as written at that level.
    public let written: String

    /// Builds the example.
    public init(groupID: String, spoken: String, writtenLabel: String, written: String) {
        self.groupID = groupID
        self.spoken = spoken
        self.writtenLabel = writtenLabel
        self.written = written
    }
}

/// The accent a row's icon tile and a note are washed in; a closed set, since the palette is the design's.
public enum SettingsTint: Sendable, Equatable, CaseIterable {
    /// Teal, dictation's colour.
    case dictation
    /// Lilac, the colour of AI suggestions.
    case suggestion
    /// Amber.
    case amber
    /// Blue, for information.
    case info
    /// Mint.
    case mint
    /// Grey.
    case neutral
    /// Red, for what cannot be undone.
    case danger
}

/// What sits at the left of a row: a tinted symbol, or an application's own icon.
public enum SettingsIcon: Sendable, Equatable {
    /// An SF Symbol on a tile washed in its tint.
    case symbol(String, SettingsTint)
    /// The icon of the application the row is about.
    case application(bundleIdentifier: String, name: String)
}

/// How a row sits in its card.
public enum SettingsRowStyle: Sendable, Equatable {
    /// A full-width line.
    case standard
    /// A smaller card inside the card, belonging to the row above it.
    case inset
    /// A lone button that adds to the list above it.
    case add
}

/// A sentence with keycaps inside it, such as "Double-tap ⌃ ⌥ to keep listening".
public struct SettingsKeyedSentence: Sendable, Equatable {
    /// The words before the keys.
    public let before: String
    /// The keys, as keycaps.
    public let keys: [String]
    /// The words after the keys.
    public let after: String

    /// The sentence as plain text, for VoiceOver and search.
    public var text: String {
        [before, keys.joined(separator: " "), after].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Builds the sentence.
    public init(before: String, keys: [String], after: String) {
        self.before = before
        self.keys = keys
        self.after = after
    }
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
    /// The tile at the left, when the row has one.
    public let icon: SettingsIcon?
    /// A short word beside the label, such as "NEW".
    public let badge: String?
    /// A second line with keycaps in it, drawn in place of ``explanation``.
    public let keyedExplanation: SettingsKeyedSentence?
    /// How the row sits in its card.
    public let style: SettingsRowStyle

    public var isEnabled: Bool { unavailability == nil }

    /// What VoiceOver reads, including why the row is off, which grey alone does not say.
    public var accessibilityLabel: String {
        let spokenLabel = badge == BetaFeature.label ? BetaFeature.accessibilityName(label) : label
        let parts = [spokenLabel, explanation ?? keyedExplanation?.text, unavailability]
            .compactMap(\.self).filter { !$0.isEmpty }
        // A lone label is read as a name, so only a label with more after it gains a full stop.
        return parts.count == 1 ? parts[0] : parts.map(Self.sentence).joined(separator: " ")
    }

    /// A part ending in a full stop, unless it already ends in one or in a question or exclamation mark.
    static func sentence(_ part: String) -> String {
        guard let last = part.last, !".?!".contains(last) else { return part }
        return part + "."
    }

    /// Builds a row; operable, plain and without an icon unless told otherwise.
    public init(
        id: String,
        label: String,
        explanation: String? = nil,
        control: SettingsControl,
        unavailability: String? = nil,
        icon: SettingsIcon? = nil,
        badge: String? = nil,
        keyedExplanation: SettingsKeyedSentence? = nil,
        style: SettingsRowStyle = .standard
    ) {
        self.id = id
        self.label = label
        self.explanation = explanation
        self.control = control
        self.unavailability = unavailability
        self.icon = icon
        self.badge = badge
        self.keyedExplanation = keyedExplanation
        self.style = style
    }

    /// The reason drawn on the row: its own, unless the pane already says the same above its cards.
    public func unavailability(besides pane: String?) -> String? {
        unavailability == pane ? nil : unavailability
    }

    /// The same row with a tile at the left.
    public func with(icon: SettingsIcon) -> SettingsRow {
        SettingsRow(
            id: id, label: label, explanation: explanation, control: control,
            unavailability: unavailability, icon: icon, badge: badge,
            keyedExplanation: keyedExplanation, style: style)
    }

    /// The same row with a short word beside its label.
    public func with(badge: String) -> SettingsRow {
        SettingsRow(
            id: id, label: label, explanation: explanation, control: control,
            unavailability: unavailability, icon: icon, badge: badge,
            keyedExplanation: keyedExplanation, style: style)
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
    /// The accent the note is washed in.
    public let tint: SettingsTint

    /// Builds a note, washed in blue unless told otherwise.
    public init(symbolName: String, message: String, tint: SettingsTint = .info) {
        self.symbolName = symbolName
        self.message = message
        self.tint = tint
    }
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

    /// The shortcut in force, as the keycaps it is drawn on, and which shortcut it is.
    case shortcut(action: ShortcutAction, keys: [String])

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

    /// Words standing in for a value not known yet, drawn in the body font: "Nothing yet".
    case placeholder(String)

    /// A fact that is fine, drawn with a green dot: "On-device".
    case status(String)

    /// The languages being listened for as removable chips, and the ones that can be added.
    case languages(chips: [SettingsChip], add: [SettingsOption])
}

/// One removable chip: what it says, and the change removing it asks for, absent when it cannot go.
public struct SettingsChip: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// What pressing × asks for, or `nil` when the chip is the last one and has to stay.
    public let removal: SettingsChange?

    /// Builds a chip.
    public init(id: String, title: String, removal: SettingsChange?) {
        self.id = id
        self.title = title
        self.removal = removal
    }
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
    case dictationEnabled
    case handsFreeEnabled
    case clipboardEnabled
    case showsFloatingButton
    case shrinksToGripWhenIdle
    case minimisesWhileDictating
    case playsSoundWhenRecordingStarts
    case opensAtLogin
    case checksForUpdatesAutomatically
    case installsUpdatesAutomatically
    case sharesUsageStatistics
    case sendsCrashReports
    case suggestionsEnabled
    case quietSuggestions
}

/// Everything the user can ask for on this screen; only ``SettingsEditor`` decides what happens.
public enum SettingsChange: Sendable, Equatable {
    case toggle(SettingsToggleField, isOn: Bool)
    case activation(HotkeyActivation)
    case anchor(DockAnchor)
    case shortcut(ShortcutAction, HotkeyBinding)
    case tidying(SettingsTidyingLevel)
    case spokenLanguage(LanguageCode, isSpoken: Bool)
    /// How long the user pauses while speaking.
    case pauses(PauseLength)
    case retention(days: Int)
    case appearance(AppAppearance)
    /// How much of the front application a dictation reads.
    case contextLevel(ContextLevel)
    /// The input device dictation opens, by UID; nil follows the system default.
    case microphone(uid: String?)
    case handsFreeDoubleTap(milliseconds: Int)
    /// How long a press may last and still count as a tap.
    case handsFreeHold(milliseconds: Int)
    /// Seconds of quiet that end a recording no key is holding; 0 is off.
    case endOnSilence(seconds: Int)

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

    /// Opens the clipboard exclusion manager.
    case manageClipboardExclusions

    /// Pauses clipboard capture for one hour, or resumes it early.
    case pauseClipboardCapture(isOn: Bool)

    /// Asks the update feed now rather than waiting for the next scheduled check.
    case checkForUpdatesNow

    /// Asks the user to pick an application to turn suggestions off in, which stores nothing until one is picked.
    case chooseApplicationToTurnOffSuggestions

    /// Fetches the suggestion model again after a failed attempt.
    case retrySuggestionModel

    /// Writes a user-selected local archive of the personal dictionary and snippets.
    case exportPersonalData

    /// Merges a user-selected local archive into the personal dictionary and snippets.
    case importPersonalData

    /// Opens a System Settings pane to resolve an Apple Intelligence availability notice.
    case openSystemSettings(SystemSettingsPane)

    /// Opens a page of the main window that has no row in its sidebar.
    case openPage(MainTab)

    /// Whether this asks for something to happen now rather than for something to be stored.
    public var isRequestToAct: Bool {
        switch self {
        case .checkForUpdatesNow, .chooseApplicationToTurnOffSuggestions, .retrySuggestionModel,
            .exportPersonalData, .importPersonalData, .manageClipboardExclusions, .pauseClipboardCapture,
            .openSystemSettings, .openPage:
            true
        default: false
        }
    }
}
