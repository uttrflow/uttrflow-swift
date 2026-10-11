import UttrflowSettings

extension SettingsPresenter {
    // MARK: - Dictation

    /// Dictation: how it is transcribed, where the words go, the clean-up steps, and what was learned.
    static func dictation(
        _ settings: Settings,
        _ capabilities: SettingsCapabilities,
        _ personalisation: SettingsPersonalisation
    ) -> SettingsPane {
        let availabilityGroups = [foundationModelAvailabilityRow(capabilities)].compactMap { row in
            row.map { SettingsGroup(id: "tidyingAvailability", title: "Clean-up availability", rows: [$0]) }
        }
        return SettingsPane(
            tab: .dictation,
            title: title(of: .dictation),
            banner: nil,
            groups: [
                SettingsDestinations.places(
                    settings.destinations, recentApps: personalisation.recentDictationApps),
                SettingsDestinations.adapterModes(
                    settings.destinations, recentApps: personalisation.recentDictationApps),
                SettingsDestinations.plainTextApps(
                    personalisation.plainTextApps, overrides: settings.destinations),

                SettingsDestinations.steps(settings.cleaning, previewer: capabilities.cleaningPreviewer),
                SettingsGroup(
                    id: "learned",
                    title: "What Uttrflow has picked up",
                    rows: [
                        toggleRow(
                            .learnsFromDictation,
                            label: "Learn from my dictation",
                            explanation:
                                "On in every app you have not turned off. Off, no new words are learned anywhere.",
                            settings, capabilities
                        ).with(icon: .symbol("brain", .amber)),
                        learnedWordsRow(personalisation),
                    ]),
                personalDataTransferGroup,
                pages,
            ].compactMap(\.self) + availabilityGroups,
            callout: SettingsCallout(
                symbolName: "info.circle",
                message:
                    "Dictation runs on this Mac, so it works with or without an internet "
                    + "connection.",
                tint: .dictation))
    }

    /// How many words Uttrflow knows from the user, and the way to the page that lists them.
    static func learnedWordsRow(_ personalisation: SettingsPersonalisation) -> SettingsRow {
        let words = personalisation.learnedWords + personalisation.addedWords
        return SettingsRow(
            id: "learnedWords",
            label: "Words it learned from you",
            explanation: words == 0
                ? "Names and terms appear here as you dictate them"
                : counted(words, "name or term", "names and terms"),
            control: .action(title: "Open Dictionary", change: .openPage(.dictionary)),
            icon: .symbol("book.closed", .amber))
    }

    /// Local backup and restore controls for the words and snippets a person has built up.
    static let personalDataTransferGroup = SettingsGroup(
        id: "personalDataTransfer",
        title: "Your words and snippets",
        rows: [
            SettingsRow(
                id: "exportPersonalData",
                label: "Export personal data",
                explanation: "Save your dictionary and snippets as a local JSON file.",
                control: .action(title: "Export…", change: .exportPersonalData),
                icon: .symbol("square.and.arrow.up", .info)),
            SettingsRow(
                id: "importPersonalData",
                label: "Import personal data",
                explanation: "Merge a local backup. Existing words and triggers are kept.",
                control: .action(title: "Import…", change: .importPersonalData),
                icon: .symbol("square.and.arrow.down", .info)),
        ])

    /// The main window's page that has no sidebar row and no tab here, as a row that opens it.
    static let pages = SettingsGroup(
        id: "pages",
        title: "More in the Uttrflow window",
        rows: [
            pageRow(.corrections, explanation: "What your dictionary changed after it heard you.")
        ])

    /// A row that opens one page of the main window.
    private static func pageRow(_ page: MainTab, explanation: String) -> SettingsRow {
        SettingsRow(
            id: "page.\(page.rawValue)", label: SidebarPresenter.title(for: page),
            explanation: explanation, control: .action(title: "Open", change: .openPage(page)),
            icon: .symbol("text.badge.checkmark", .info))
    }

}
