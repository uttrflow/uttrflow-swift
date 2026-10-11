import UttrflowCore
import UttrflowSettings

extension SettingsPresenter {
    // MARK: - Languages

    /// The row saying which languages Uttrflow listens for, as chips with the rest to add.
    static func listenForRow(_ settings: Settings) -> SettingsRow {
        let spoken = settings.profile.preferredLanguages
        let offered = SettingsLanguage.offered
        return SettingsRow(
            id: "spokenLanguages",
            label: "Listen for",
            explanation: "Uttrflow needs at least one",
            control: .languages(
                chips: offered.filter { spoken.contains($0.code) }.map { language in
                    SettingsChip(
                        id: language.id, title: language.name,
                        // The last language cannot come off, so its chip offers no ×.
                        removal: spoken.count > 1 ? .spokenLanguage(language.code, isSpoken: false) : nil)
                },
                add: offered.filter { !spoken.contains($0.code) }.map { language in
                    SettingsOption(
                        id: language.id, title: language.name,
                        change: .spokenLanguage(language.code, isSpoken: true))
                }),
            icon: .symbol("globe", .info))
    }

    /// The row saying how long the user pauses while speaking, so a long pause does not end a sentence.
    static func pausesRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "pauses",
            label: "Pauses while you speak",
            explanation: "Longer means Uttrflow waits longer before a pause ends a sentence",
            control: .segmented(
                options: PauseLength.allCases.map { pauses in
                    let title: String =
                        switch pauses {
                        case .usual: "Usual"
                        case .long: "Long"
                        case .veryLong: "Very long"
                        }
                    return SettingsOption(id: pauses.rawValue, title: title, change: .pauses(pauses))
                },
                selectedID: settings.profile.pauses.rawValue),
            icon: .symbol("pause.circle", .info))
    }

    /// The tidying row, shared by every screen that offers the level.
    static func tidyingRow(
        _ level: SettingsTidyingLevel, _ capabilities: SettingsCapabilities
    ) -> SettingsRow {
        SettingsRow(
            id: "tidyingLevel",
            label: SettingsTidyingLevel.rowLabel,
            explanation: SettingsTidyingLevel.rowExplanation,
            control: .segmented(
                options: SettingsTidyingLevel.allCases.map { option in
                    SettingsOption(id: option.rawValue, title: option.title, change: .tidying(option))
                },
                selectedID: level.rawValue),
            unavailability: SettingsEditor.unavailability(ofTidying: .standard, given: capabilities),
            icon: .symbol("wand.and.stars", .suggestion))
    }

    /// The Apple Intelligence cause and its recovery, shown beside the tidying level when it is unavailable.
    static func foundationModelAvailabilityRow(_ capabilities: SettingsCapabilities) -> SettingsRow? {
        guard case .unavailable(let reason) = capabilities.foundationModelAvailability else { return nil }
        let label: String
        let explanation: String
        let control: SettingsControl
        switch reason {
        case .appleIntelligenceDisabled:
            label = "Apple Intelligence is switched off"
            explanation = "Turn it on in System Settings to use full clean-up."
            control = .action(
                title: "Open System Settings", change: .openSystemSettings(.appleIntelligence))
        case .modelNotReady:
            label = "Apple Intelligence model is downloading"
            explanation = "Full clean-up will be available when the download finishes."
            control = .status("Downloading")
        case .deviceNotEligible:
            label = "This Mac cannot run Apple Intelligence"
            explanation = "Uttrflow will continue cleaning up with its built-in rules."
            control = .status("Unavailable")
        case .other(let detail):
            label = "Apple Intelligence is unavailable"
            explanation = detail
            control = .status("Unavailable")
        }
        return SettingsRow(
            id: "foundationModelAvailability", label: label, explanation: explanation,
            control: control, icon: .symbol("sparkles", .suggestion))
    }

    /// The sentence the example is spoken as; it needs filler and a slip to show anything.
    static let exampleSpoken = "um so i think we should uh ship it on friday"

    /// The example as the rules every level ends in write it; a test runs them and fails when the two differ.
    static let exampleWritten = "So I think we should ship it on Friday."

    /// The example under the level in force.
    static func tidyExample(_ level: SettingsTidyingLevel) -> SettingsTidyExample {
        SettingsTidyExample(
            groupID: "tidying", spoken: exampleSpoken,
            writtenLabel: "Uttrflow writes · \(level.title)", written: exampleWritten)
    }

    /// Languages: which languages Uttrflow listens for, and how much it tidies, shown on an example.
    static func languages(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsPane {
        let level = SettingsTidyingLevel(preference: settings.engines.transformerPreference)
        return SettingsPane(
            tab: .languages,
            title: title(of: .languages),
            banner: nil,
            groups: [
                SettingsGroup(
                    id: "spoken", title: "Languages you speak",
                    rows: [listenForRow(settings), pausesRow(settings)]),
                SettingsGroup(
                    id: "tidying", title: "Clean-up",
                    rows: [tidyingRow(level, capabilities)]
                        + [foundationModelAvailabilityRow(capabilities)].compactMap(\.self)),
            ],
            callout: SettingsCallout(
                symbolName: "info.circle",
                message:
                    "Mixing English and Hindi in one sentence is expected and handled. Hindi is "
                    + "written in Latin letters the way people type it, never Devanagari, never "
                    + "translated."),
            example: tidyExample(level))
    }

}
