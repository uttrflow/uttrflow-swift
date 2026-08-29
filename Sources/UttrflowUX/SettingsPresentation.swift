public import UttrflowCore
public import UttrflowSettings

// MARK: - What a screen is made of

/// One entry in the sidebar.
///
/// Built from ``SettingsTab/allCases`` rather than written out, so a tab cannot be
/// added to the destination and then quietly missing from the window.
public struct SettingsTabItem: Sendable, Equatable, Identifiable {
    public let tab: SettingsTab
    public let title: String
    public let symbolName: String

    public var id: SettingsTab { tab }
}

/// A whole screen: what it is called, and everything on it.
///
/// All four tabs are this one shape. A tab is a list of cards and, at most, a
/// reassurance above them and a note below — so the view that draws one draws all of
/// them, and a fifth tab needs no new drawing code.
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
    ///
    /// A control the user can move that changes nothing is worse than one they cannot:
    /// it teaches them the app is broken. Every row that is off is off for a stated
    /// reason, whether the reason is a missing capability or another setting it depends
    /// on, and the view has only to show what is here.
    public let unavailability: String?

    public var isEnabled: Bool { unavailability == nil }

    /// What VoiceOver reads. The reason a row is off has to be spoken, not conveyed by
    /// the row looking grey.
    public var accessibilityLabel: String {
        [label, explanation, unavailability].compactMap(\.self).joined(separator: ". ")
    }

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

/// The thing on the right-hand side of a row.
///
/// Deliberately a closed set. Every case is something the design already draws, and a
/// row can only ask for one of them, so the view has no case it might not handle and
/// no chance to invent a control of its own.
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

    /// A button that removes something.
    ///
    /// Its own case rather than a general "button" because every one of them destroys
    /// data. The view draws them destructively without being told to, and nothing that
    /// merely navigates can be smuggled in here later and inherit that treatment.
    case removal(SettingsRemoval)
}

/// A destructive button: what it says, what it removes, and what it asks first.
public struct SettingsRemoval: Sendable, Equatable {
    public let reset: SettingsReset
    /// What the button says. Ends in an ellipsis exactly when pressing it asks first,
    /// which is the platform's own promise about what a button is about to do.
    public let title: String
    /// What the user is shown before anything goes, or `nil` when they are not asked.
    ///
    /// Optional rather than always present because being asked is itself a cost: a
    /// dialogue in front of a recoverable action teaches people to dismiss dialogues,
    /// and the one in front of the irreversible action is then dismissed too.
    public let confirmation: SettingsConfirmation?

    public init(reset: SettingsReset, title: String, confirmation: SettingsConfirmation?) {
        self.reset = reset
        self.title = title
        self.confirmation = confirmation
    }
}

/// The question asked before something irreversible happens.
public struct SettingsConfirmation: Sendable, Equatable {
    public let title: String
    /// What will be removed, counted. Never "Are you sure?": a user who is told a real
    /// number can decide, and a user who is asked whether they are sure can only guess
    /// at what they are being asked about.
    public let message: String
    public let confirmTitle: String
    public let cancelTitle: String

    /// The button Return presses.
    ///
    /// Always the one that removes nothing, and computed rather than stored so that it
    /// cannot be set to anything else. Nothing here is destructive by accident.
    public var defaultTitle: String { cancelTitle }

    public init(title: String, message: String, confirmTitle: String, cancelTitle: String) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
    }
}

/// One choice in a segmented control or a pop-up, and what choosing it means.
///
/// The change travels with the option so that picking one is a matter of handing back
/// what was already decided here. Nothing downstream has to work out what an option id
/// stood for, which is the step at which a view starts making decisions.
public struct SettingsOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let change: SettingsChange
}

// MARK: - Changes

/// A switch the user can throw, named so a row and a change cannot disagree about
/// which field they are about.
public enum SettingsToggleField: String, Sendable, Equatable, CaseIterable {
    case showsFloatingButton
    case shrinksToGripWhenIdle
    case minimisesWhileDictating
    case playsSoundWhenRecordingStarts
    case opensAtLogin
}

/// Everything the user can ask for on this screen.
///
/// One vocabulary for every tab: the view reports a change, ``SettingsEditor`` is the
/// only thing that decides whether it may happen, and no control anywhere writes to
/// ``Settings`` itself.
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
}
