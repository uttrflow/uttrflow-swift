// The Style page: the tidying and language cards, and the worked example under them.
public import UttrflowSettings

/// The same sentence tidied both ways; fixed copy, since the example needs filler and a slip to show.
public struct StyleExample: Sendable, Equatable {
    /// The heading over the example.
    public let heading: String
    /// The label on the spoken line.
    public let spokenLabel: String
    /// The sentence as spoken.
    public let spoken: String
    /// One line per level, in ``SettingsTidyingLevel/allCases`` order, so the current row can be marked.
    public let outcomes: [StyleOutcome]

    /// Builds the example.
    public init(
        heading: String, spokenLabel: String, spoken: String, outcomes: [StyleOutcome]
    ) {
        self.heading = heading
        self.spokenLabel = spokenLabel
        self.spoken = spoken
        self.outcomes = outcomes
    }
}

/// What one level of tidying makes of the example sentence.
public struct StyleOutcome: Sendable, Equatable, Identifiable {
    /// The level.
    public let level: SettingsTidyingLevel
    /// The sentence at that level.
    public let text: String
    /// Whether this is the level in force.
    public let isCurrent: Bool

    /// The level's stored name.
    public var id: String { level.rawValue }

    /// Builds an outcome.
    public init(level: SettingsTidyingLevel, text: String, isCurrent: Bool) {
        self.level = level
        self.text = text
        self.isCurrent = isCurrent
    }
}

/// Everything the style page is drawn from.
public struct StylePageSnapshot: Sendable, Equatable {
    /// The user's settings.
    public let settings: Settings
    /// What this Mac can run, so a level it cannot reach says why rather than moving and doing nothing.
    public let capabilities: SettingsCapabilities

    /// Builds a snapshot.
    public init(settings: Settings, capabilities: SettingsCapabilities) {
        self.settings = settings
        self.capabilities = capabilities
    }
}

/// What the style page shows.
public struct StylePagePresentation: Sendable, Equatable {
    /// The title and caption across the top.
    public let chrome: MainPageChrome
    /// ``SettingsGroup`` verbatim, so a change reported here goes through the same ``SettingsEditor``.
    public let groups: [StylePageGroup]
    /// The worked example.
    public let example: StyleExample
    /// The note about languages.
    public let callout: MainCallout

    /// Builds the page from its parts.
    public init(
        chrome: MainPageChrome, groups: [StylePageGroup], example: StyleExample,
        callout: MainCallout
    ) {
        self.chrome = chrome
        self.groups = groups
        self.example = example
        self.callout = callout
    }
}

/// A card on the style page, and where the example sits relative to it.
public struct StylePageGroup: Sendable, Equatable, Identifiable {
    /// The card.
    public let group: SettingsGroup
    /// Whether the worked example is drawn under this card; only the tidying card has one.
    public let isFollowedByExample: Bool

    /// The card's identifier.
    public var id: String { group.id }

    /// Builds a group.
    public init(group: SettingsGroup, isFollowedByExample: Bool) {
        self.group = group
        self.isFollowedByExample = isFollowedByExample
    }
}

/// Tidying and languages as ``SettingsPresenter`` builds them; no Off, since a floor engine always runs.
public enum StylePagePresenter {
    /// Draws the Style page from a snapshot.
    public static func page(for snapshot: StylePageSnapshot) -> StylePagePresentation {
        let level = SettingsTidyingLevel(preference: snapshot.settings.engines.transformerPreference)
        return StylePagePresentation(
            chrome: MainPageChrome(
                title: "Style",
                caption: "How much tidying Uttrflow does to what you actually said."),
            groups: [
                StylePageGroup(group: tidying(level, snapshot), isFollowedByExample: true),
                StylePageGroup(group: languages(snapshot), isFollowedByExample: false),
            ],
            example: example(current: level),
            callout: MainCallout(
                symbolName: "globe",
                message: """
                    Tidying is strongest in English. Hindi and Hinglish get punctuation and \
                    spacing, not rewriting — and anything Uttrflow does change shows up in \
                    Corrections.
                    """))
    }

    // MARK: - Tidying

    /// The tidying card, with the level this Mac cannot reach explained.
    static func tidying(
        _ level: SettingsTidyingLevel, _ snapshot: StylePageSnapshot
    ) -> SettingsGroup {
        SettingsGroup(
            id: "tidying",
            title: "Tidying up",
            rows: [
                SettingsRow(
                    id: "tidyingLevel",
                    label: SettingsTidyingLevel.rowLabel,
                    explanation: SettingsTidyingLevel.rowExplanation,
                    control: .segmented(
                        options: SettingsTidyingLevel.allCases.map {
                            SettingsOption(id: $0.rawValue, title: $0.title, change: .tidying($0))
                        },
                        selectedID: level.rawValue),
                    unavailability: SettingsEditor.unavailability(
                        ofTidying: .standard, given: snapshot.capabilities))
            ])
    }

    /// The worked example with the current level marked.
    static func example(current: SettingsTidyingLevel) -> StyleExample {
        StyleExample(
            heading: "The same sentence, both ways",
            spokenLabel: "You said",
            spoken: "um so i think we should uh ship it on friday",
            outcomes: SettingsTidyingLevel.allCases.map { level in
                StyleOutcome(level: level, text: tidied(at: level), isCurrent: level == current)
            })
    }

    /// The example at each level; a `switch`, so a third level cannot be added without writing its line.
    static func tidied(at level: SettingsTidyingLevel) -> String {
        switch level {
        case .light: "Um, so I think we should, uh, ship it on Friday."
        case .standard: "I think we should ship it on Friday."
        }
    }

    // MARK: - Languages

    /// The languages card as the settings window builds it, saying on the row that the last one cannot go.
    static func languages(_ snapshot: StylePageSnapshot) -> SettingsGroup {
        let spoken = snapshot.settings.profile.preferredLanguages
        return SettingsGroup(
            id: "languages",
            title: "Languages",
            rows: SettingsLanguage.offered.map { language in
                let isSpoken = spoken.contains(language.code)
                return SettingsRow(
                    id: language.id,
                    label: language.name,
                    explanation: language.endonym,
                    control: .tick(
                        isTicked: isSpoken,
                        change: .spokenLanguage(language.code, isSpoken: !isSpoken)),
                    unavailability: isSpoken && spoken.count == 1
                        ? "Uttrflow needs at least one language to listen for." : nil)
            })
    }
}
