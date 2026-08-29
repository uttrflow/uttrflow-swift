public import UttrflowSettings

/// The same sentence, tidied both ways.
///
/// The one honest way to explain a setting whose effect is a matter of taste: rather
/// than describing what "Standard" does, show it. Fixed copy rather than the user's own
/// last dictation, because the example has to contain filler words and a grammar slip
/// for the difference to be visible at all, and their last sentence probably did not.
public struct StyleExample: Sendable, Equatable {
    public let heading: String
    public let spokenLabel: String
    public let spoken: String
    /// One line per level, in ``SettingsTidyingLevel/allCases`` order, so the row the
    /// user is currently on can be marked.
    public let outcomes: [StyleOutcome]

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
    public let level: SettingsTidyingLevel
    public let text: String
    public let isCurrent: Bool

    public var id: String { level.rawValue }

    public init(level: SettingsTidyingLevel, text: String, isCurrent: Bool) {
        self.level = level
        self.text = text
        self.isCurrent = isCurrent
    }
}

/// Everything the style page is drawn from.
public struct StylePageSnapshot: Sendable, Equatable {
    public let settings: Settings
    /// What this Mac can actually run, so a level it cannot reach says why rather than
    /// moving and doing nothing.
    public let capabilities: SettingsCapabilities

    public init(settings: Settings, capabilities: SettingsCapabilities) {
        self.settings = settings
        self.capabilities = capabilities
    }
}

/// What the style page shows.
public struct StylePagePresentation: Sendable, Equatable {
    public let chrome: MainPageChrome
    /// ``SettingsGroup`` verbatim, not a copy of its shape.
    ///
    /// The settings window already has a tested vocabulary for a card of rows with
    /// controls on them, and a change reported from here goes through the same
    /// ``SettingsEditor`` as one reported from there. Two screens offering one choice
    /// must not be two chances to apply it differently.
    public let groups: [StylePageGroup]
    public let example: StyleExample
    public let callout: MainCallout

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
    public let group: SettingsGroup
    /// Whether the worked example is drawn under this card. Only the tidying card has
    /// one, and putting the decision here keeps the view from knowing which card that is.
    public let isFollowedByExample: Bool

    public var id: String { group.id }

    public init(group: SettingsGroup, isFollowedByExample: Bool) {
        self.group = group
        self.isFollowedByExample = isFollowedByExample
    }
}

/// Turns the two choices that change how Uttrflow writes into a page of their own.
///
/// Tidying and languages are already settings, and they are here as well because they
/// are the two the user revisits: everything else in the settings window is set once.
/// Nothing is duplicated to achieve that — both cards are the ones ``SettingsPresenter``
/// builds, reported through ``SettingsChange`` and applied by ``SettingsEditor``.
///
/// **On Light/Standard versus Off/Light/Standard.** The `Settings-Dictation` artboard
/// offers three levels and this page offers two. Two is right, and it is right in code
/// as well as here: ``SettingsTidyingLevel`` has no "off" because the transformer
/// preference order always ends in a floor that can handle anything, so something always
/// runs. An "Off" the pipeline cannot be in would be a switch that changes nothing —
/// the one kind of control this product refuses to draw.
public enum StylePagePresenter {
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

    static func example(current: SettingsTidyingLevel) -> StyleExample {
        StyleExample(
            heading: "The same sentence, both ways",
            spokenLabel: "You said",
            spoken: "um so i think we should uh ship it on friday",
            outcomes: SettingsTidyingLevel.allCases.map { level in
                StyleOutcome(level: level, text: tidied(at: level), isCurrent: level == current)
            })
    }

    /// The example sentence at each level. A `switch`, so a third level could not be
    /// added without somebody writing down what it makes of this sentence.
    static func tidied(at level: SettingsTidyingLevel) -> String {
        switch level {
        case .light: "Um, so I think we should, uh, ship it on Friday."
        case .standard: "I think we should ship it on Friday."
        }
    }

    // MARK: - Languages

    /// The languages card, built exactly as the settings window builds it.
    ///
    /// Including the rule that the last ticked language cannot come off, which is said
    /// on the row before it is tried rather than refused afterwards.
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
