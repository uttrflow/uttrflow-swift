// The choices the settings screens offer, stated as outcomes. See `Docs/ux-settings-model.md`.
public import UttrflowCore
public import UttrflowPredict
import UttrflowSettings

// MARK: - Tidying

/// How much Uttrflow tidies what was said, with no "off" because a floor always runs.
public enum SettingsTidyingLevel: String, Sendable, Equatable, CaseIterable {
    /// Punctuation, capitalisation and spacing. The floor, and nothing above it.
    case light
    /// Filler words removed and grammar repaired as well, wherever an engine can.
    case standard

    /// What the level is called on screen.
    public var title: String {
        switch self {
        case .light: "Light"
        case .standard: "Standard"
        }
    }

    /// What the row is called on both screens that draw it.
    public static let rowLabel = "How much Uttrflow tidies"
    /// What the row says underneath on both screens that draw it.
    public static let rowExplanation = """
        Both levels remove filler sounds and stammers and add punctuation. Standard also \
        repairs grammar slips with an on-device model, which adds a moment to each dictation. \
        Neither level changes, reorders or drops the words you meant.
        """
}

extension SettingsTidyingLevel {
    /// Reads the level back out of a stored preference order: anything above the floor is standard.
    public init(preference: [TransformerKind]) {
        let resolved = EngineConfiguration(speech: .whisperKit, transformerPreference: preference)
            .resolvedTransformerPreference
        self = resolved.contains { $0 != .rules } ? .standard : .light
    }

    /// The preference order this level means, floor included.
    public var preference: [TransformerKind] {
        switch self {
        case .light: SettingsEngines.normalised([])
        case .standard: SettingsEngines.normalised(TransformerKind.selectable)
        }
    }
}

// MARK: - The preference order

/// The one place that knows what a valid clean-up preference looks like.
public enum SettingsEngines {
    /// Drops kinds this build lacks and appends the floor. See `Docs/ux-settings-model.md`.
    public static func normalised(_ preference: [TransformerKind]) -> [TransformerKind] {
        let selectable = Set(TransformerKind.selectable)
        var ordered: [TransformerKind] = []
        for kind in preference {
            guard kind != floor, selectable.contains(kind), !ordered.contains(kind) else {
                continue
            }
            ordered.append(kind)
        }
        return ordered + [floor]
    }

    /// The kind that declines nothing, and so the only safe last entry.
    public static let floor = TransformerKind.rules
}

// MARK: - Retention

/// How long transcripts are kept, offering only periods the store round-trips unchanged.
public enum SettingsRetention {
    /// Finite periods offered in the menu, all within the maximum retention window.
    public static let finiteOfferedDays = [1, 3, 7, 14, 30, 90]

    /// All saved values offered in the menu, ordered because they are drawn in this order.
    public static let offeredDays = [Settings.keepAlwaysDays] + finiteOfferedDays

    /// Whether a period means "until I delete it" rather than a number of days.
    public static func isAlways(days: Int) -> Bool {
        days >= Settings.keepAlwaysDays
    }

    /// How a period reads in a pop-up.
    public static func title(days: Int) -> String {
        if isAlways(days: days) { return "Always" }
        return days == 1 ? "1 day" : "\(days) days"
    }
}

// MARK: - Languages

/// A language Uttrflow can be told to listen for.
public struct SettingsLanguage: Sendable, Equatable, Identifiable {
    public let code: LanguageCode
    /// What it is called in English, which is the language this screen is written in.
    public let name: String
    /// What it is called in itself, for a speaker scanning the list for their own.
    public let endonym: String?

    public var id: String { code.value }
}

extension SettingsLanguage {
    /// The languages V1 transcribes, listed so an unchosen one still appears to be chosen.
    public static let offered: [SettingsLanguage] = [
        SettingsLanguage(code: .english, name: "English", endonym: nil),
        SettingsLanguage(code: .hindi, name: "Hindi", endonym: "हिन्दी"),
    ]
}

// MARK: - Accepting a suggestion

extension AcceptKey {
    /// What the key is called on screen, spelled as a keyboard is rather than as a symbol.
    public var title: String {
        switch self {
        case .tab: "Tab"
        case .rightArrow: "Right arrow"
        case .optionTab: "Option-Tab"
        }
    }

    /// The consequence of this key that holds in every application.
    public var explanation: String? {
        switch self {
        case .tab: nil
        case .rightArrow: "Escape will not dismiss suggestions."
        case .optionTab: nil
        }
    }

    /// Describes the native Tab behavior this key leaves available in the application's kind.
    func explanation(for kind: AppKind?) -> String? {
        switch self {
        case .tab:
            return Self.tabCollisionExplanation(for: kind)
        case .rightArrow:
            guard let consequence = explanation else { return nil }
            return "\(Self.nativeTabExplanation(for: kind)) \(consequence)"
        case .optionTab:
            return Self.nativeTabExplanation(for: kind)
        }
    }

    /// Names the native Tab action intercepted when Tab itself accepts a suggestion.
    private static func tabCollisionExplanation(for kind: AppKind?) -> String? {
        switch kind {
        case .terminal: "Tab accepts suggestions instead of shell completion."
        case .codeEditor: "Tab accepts suggestions instead of indentation and editor completion."
        case .sqlEditor: "Tab accepts suggestions instead of indentation and SQL completion."
        case .spreadsheet: "Tab accepts suggestions instead of cell navigation."
        case .documentEditor: "Tab accepts suggestions instead of the document editor's own behavior."
        case .notes: "Tab accepts suggestions instead of the notes app's own behavior."
        case .chat, .email, nil: nil
        }
    }

    /// Names the native Tab action from the same destination kind that selects the accept key.
    private static func nativeTabExplanation(for kind: AppKind?) -> String {
        switch kind {
        case .terminal: "Leaves Tab to the shell's own completion."
        case .codeEditor: "Leaves Tab to indentation and editor completion."
        case .sqlEditor: "Leaves Tab to indentation and SQL completion."
        case .spreadsheet: "Leaves Tab to cell navigation."
        case .documentEditor: "Leaves Tab to the document editor's own behavior."
        case .notes: "Leaves Tab to the notes app's own behavior."
        case .chat, .email, nil: "Leaves Tab available in this app."
        }
    }
}
