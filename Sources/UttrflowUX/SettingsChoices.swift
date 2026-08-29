public import UttrflowCore

// MARK: - Tidying

/// How much Uttrflow is allowed to rewrite what was said.
///
/// Stated as an outcome rather than as a list of engines. §16 holds here as much as it
/// does on the floating button: the user chooses how much help they want, never which
/// implementation gives it to them, so a change of engine is never a change of screen.
///
/// There is deliberately no "off". The preference order always ends in a floor that can
/// handle anything, so something always runs; offering "off" would promise a state the
/// pipeline has no way to be in.
public enum SettingsTidyingLevel: String, Sendable, Equatable, CaseIterable {
    /// Punctuation, capitalisation and spacing. The floor, and nothing above it.
    case light
    /// Filler words removed and grammar repaired as well, wherever an engine can.
    case standard

    public var title: String {
        switch self {
        case .light: "Light"
        case .standard: "Standard"
        }
    }

    /// What the row is called, and what it says underneath — for every screen that shows
    /// it.
    ///
    /// Held here rather than at each call site because there are two of them, and they
    /// had drifted: Settings said "Tidy up what I say / Light fixes punctuation only",
    /// Style said "How much Uttrflow tidies / Light fixes punctuation and capitalisation
    /// only". A user comparing the two screens is entitled to conclude the app has two
    /// settings, or that one of the screens is lying about what Light does — and one of
    /// them was, since Light does capitalisation too.
    public static let rowLabel = "How much Uttrflow tidies"
    public static let rowExplanation = """
        Light fixes punctuation, capitalisation and spacing. Standard also removes filler \
        words and repairs grammar.
        """
}

extension SettingsTidyingLevel {
    /// Reads the level back out of a stored preference order.
    ///
    /// Anything the build can run above the floor means the user asked for the full
    /// treatment; a preference that is only the floor means they asked for less.
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

/// The trade the user is really making when they choose a speech engine: how long they
/// wait against how often they have to correct it.
public enum SettingsTranscriptionQuality: String, Sendable, Equatable, CaseIterable {
    /// The lowest latency the Mac can manage.
    case faster
    /// The fewest mistakes, at the cost of a second or two.
    case mostAccurate

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

    /// Reads the choice back out of a stored engine.
    ///
    /// An exhaustive `switch` rather than a search with a fallback: a fallback would be
    /// a branch nothing could ever take, and it would silently mislabel a newly added
    /// engine instead of refusing to compile until somebody said what it is for.
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
    /// Puts a preference order into the only shape the pipeline can run.
    ///
    /// Two rules, both enforced rather than described. Kinds this build does not
    /// contain are dropped, because a configuration written by another build must not
    /// select an engine that is not here. And the floor is appended last, always, so
    /// the pipeline cannot reach the end of the list with the text untouched — a
    /// dead-end that would lose the user their words rather than merely tidy them
    /// badly.
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

    /// The kind that declines nothing. Rules cannot invent and cannot refuse, which is
    /// exactly what makes it the only safe last entry.
    public static let floor = TransformerKind.rules
}

// MARK: - Retention

/// The retention periods the settings store keeps exactly as they are given.
///
/// Transcripts are the only thing there is a period for: audio is never written to
/// disk, so there is nothing about a recording for the user to set.
///
/// The store treats a period of zero or less as a corrupt value and quietly replaces
/// it, so a screen that offered one would show the user a choice, save it, and reopen
/// showing something else. Offering only values that survive the round trip is what
/// keeps that from happening; `SettingsRetentionTests` proves each one does by putting
/// it through `Settings` rather than by restating the store's rule here.
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
    /// The languages V1 transcribes. Held here rather than derived from the profile so
    /// that a language the user has never chosen still appears, unticked, to be chosen.
    public static let offered: [SettingsLanguage] = [
        SettingsLanguage(code: .english, name: "English", endonym: nil),
        SettingsLanguage(code: .hindi, name: "Hindi", endonym: "हिन्दी"),
    ]
}
