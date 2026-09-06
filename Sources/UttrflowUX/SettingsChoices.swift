// The choices the settings screens offer, stated as outcomes. See `Docs/ux-settings-model.md`.
public import UttrflowCore
public import UttrflowPredict

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
        Light fixes punctuation, capitalisation and spacing. Standard also removes filler \
        words and repairs grammar.
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

// MARK: - Transcription

/// The trade behind a speech engine: how long the user waits against how often they correct it.
public enum SettingsTranscriptionQuality: String, Sendable, Equatable, CaseIterable {
    /// The lowest latency the Mac can manage.
    case faster
    /// The fewest mistakes, at the cost of a second or two.
    case mostAccurate

    /// What the quality is called on screen.
    public var title: String {
        switch self {
        case .faster: "Faster"
        case .mostAccurate: "Most accurate"
        }
    }

    /// Which implementation delivers it. Never shown to the user.
    public var engine: SpeechEngineKind {
        switch self {
        case .faster: .appleSpeech
        case .mostAccurate: .whisperKit
        }
    }

    /// Reads the choice back out of a stored engine, exhaustively so a new engine must be named.
    public init(engine: SpeechEngineKind) {
        switch engine {
        case .appleSpeech: self = .faster
        case .whisperKit: self = .mostAccurate
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
    /// A day, through to a quarter. Ordered, because they are drawn in this order.
    public static let offeredDays = [1, 3, 7, 14, 30, 90]

    /// How a period reads in a pop-up.
    public static func title(days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
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

    /// Why this key rather than Tab, said only where it is not the obvious answer.
    public var explanation: String? {
        switch self {
        case .tab: nil
        case .rightArrow: "Leaves Tab to the shell's own completion."
        case .optionTab: "Leaves Tab to indent, and to the editor's own completion."
        }
    }
}
