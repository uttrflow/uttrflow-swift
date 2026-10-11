public import struct Foundation.Date
public import struct Foundation.Locale
import UttrflowClipboard
import UttrflowCore
import UttrflowPredict
public import UttrflowSettings

/// The whole Settings page, as the view is given it.
public struct SettingsWindowPresentation: Sendable, Equatable {
    public let tabs: [SettingsTabItem]
    public let selected: SettingsTab
    /// The selected tab, or every row matching the search while one is typed.
    public let pane: SettingsPane
    /// What is typed in the search field.
    public let query: String
}

/// Turns the user's settings into what the Settings page draws, naming no engine or file.
public enum SettingsPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search settings"

    /// Every tab, in the design's order, driven by ``SettingsTab/allCases`` so a new case adds a tab.
    public static func tabs() -> [SettingsTabItem] {
        SettingsTab.allCases.map { tab in
            SettingsTabItem(
                tab: tab, title: title(of: tab), symbolName: symbolName(of: tab),
                badge: tab == .suggestions ? BetaFeature.label : nil)
        }
    }

    /// What a tab is called.
    public static func title(of tab: SettingsTab) -> String {
        switch tab {
        case .general: "General"
        case .languages: "Languages"
        case .dictation: "Dictation"
        case .suggestions: "AI suggestions"
        case .privacy: "Privacy"
        case .diagnostics: "Diagnostics"
        }
    }

    /// The SF Symbol beside a tab's name.
    static func symbolName(of tab: SettingsTab) -> String {
        switch tab {
        case .general: "gearshape"
        case .languages: "globe"
        case .dictation: "mic"
        case .suggestions: "sparkles"
        case .privacy: "checkmark.shield"
        case .diagnostics: "waveform.path.ecg"
        }
    }

    /// The whole page: every tab, which one is showing, and what that one draws or the search found.
    public static func window(
        showing tab: SettingsTab,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing,
        at moment: Date = Date(),
        query: String = ""
    ) -> SettingsWindowPresentation {
        let searching = !SearchQuery.needle(in: query).isEmpty
        return SettingsWindowPresentation(
            tabs: tabs(),
            selected: tab,
            pane: searching
                ? search(
                    query, settings: settings, capabilities: capabilities,
                    personalisation: personalisation, at: moment)
                : pane(
                    for: tab, settings: settings, capabilities: capabilities,
                    personalisation: personalisation, at: moment),
            query: query)
    }

    /// One tab, drawn from the settings and what this Mac can do.
    public static func pane(
        for tab: SettingsTab,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing,
        at moment: Date = Date()
    ) -> SettingsPane {
        switch tab {
        case .general: general(settings, capabilities)
        case .languages: languages(settings, capabilities)
        case .dictation: dictation(settings, capabilities, personalisation)
        case .suggestions: suggestions(settings, personalisation, capabilities, moment)
        case .privacy: privacy(settings, capabilities, personalisation)
        // Drawn from the diagnostics the main window already holds, so there are no rows here.
        case .diagnostics:
            SettingsPane(
                tab: .diagnostics, title: title(of: .diagnostics), banner: nil, groups: [], callout: nil)
        }
    }

    // MARK: - Search

    /// Every row on every tab that mentions the query, grouped under its tab and card.
    public static func search(
        _ query: String,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing,
        at moment: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> SettingsPane {
        let groups = SettingsTab.allCases.flatMap { tab in
            let pane = pane(
                for: tab, settings: settings, capabilities: capabilities,
                personalisation: personalisation, at: moment)
            return pane.groups.compactMap { group -> SettingsGroup? in
                let heading = [pane.title, group.title].compactMap(\.self).joined(separator: " · ")
                // A card whose heading matches keeps every row, since the heading is what was looked for.
                let rows =
                    SearchQuery.matches([heading], query: query, locale: locale) { [$0] }.isEmpty
                    ? SearchQuery.matches(group.rows, query: query, locale: locale) {
                        [$0.label, $0.explanation, $0.keyedExplanation?.text]
                    }
                    : group.rows
                let kept = rows.filter { $0.style != .add }
                guard !kept.isEmpty else { return nil }
                return SettingsGroup(id: "\(tab.rawValue).\(group.id)", title: heading, rows: kept)
            }
        }
        let needle = SearchQuery.needle(in: query)
        return SettingsPane(
            tab: .general, title: "Search", banner: nil, groups: groups, callout: nil,
            emptySearch: groups.isEmpty ? "No setting mentions “\(needle)”." : nil)
    }

    /// Updating: the version, a way to ask now, and whether to be asked first, feed or no feed.
    static func updates(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsGroup {
        // Both acting rows fail together and for one reason, so they say it the same way.
        let noFeed = "This build has no update feed, so there is nothing to check."

        var rows: [SettingsRow] = []

        if let version = capabilities.versionDescription {
            rows.append(
                SettingsRow(
                    id: "version", label: "Version", control: .text(version),
                    icon: .symbol("cpu", .mint)))
        }

        rows.append(
            SettingsRow(
                id: "checkForUpdates",
                label: "Check for updates",
                explanation: capabilities.canCheckForUpdates
                    ? "Check now even when automatic checks are off." : nil,
                control: .action(title: "Check Now", change: .checkForUpdatesNow),
                unavailability: capabilities.canCheckForUpdates ? nil : noFeed,
                icon: .symbol("arrow.triangle.2.circlepath", .info)))

        rows.append(
            toggleRow(
                .checksForUpdatesAutomatically,
                label: "Check for updates automatically",
                explanation: "Checks the update feed every six hours.",
                settings, capabilities
            ).with(icon: .symbol("arrow.triangle.2.circlepath", .info)))

        rows.append(
            toggleRow(
                .installsUpdatesAutomatically,
                label: "Install updates automatically",
                explanation:
                    "Off means Uttrflow asks first. Either way it never installs mid-dictation.",
                settings, capabilities
            ).with(icon: .symbol("checkmark.shield", .dictation)))

        return SettingsGroup(id: "updates", title: "Updates", rows: rows)
    }

    // MARK: - Persona

    /// Every fact the evidence ledger records, each with its own Remove, and a reset for all of them.
    static func personaGroup(_ personalisation: SettingsPersonalisation) -> SettingsGroup {
        let items = personalisation.persona.map { item in
            SettingsRow(
                id: "persona.\(item.id)", label: item.title, explanation: item.detail,
                control: .removal(
                    SettingsRemoval(reset: .personaFact(item.fact), title: "Remove", confirmation: nil)),
                style: .inset)
        }
        guard !personalisation.persona.isEmpty else {
            return SettingsGroup(
                id: "persona", title: "What Uttrflow noticed about you",
                rows: [
                    SettingsRow(
                        id: "resetPersona", label: "Nothing noticed yet",
                        explanation:
                            "Words you use and how you write in each kind of app appear here as you dictate.",
                        control: .status("Empty"), icon: .symbol("person.crop.circle", .amber))
                ])
        }
        let count = counted(personalisation.persona.count, "thing", "things")
        let reset = SettingsRow(
            id: "resetPersona",
            label: "Reset what Uttrflow noticed",
            explanation: "Forget \(count) noticed from your dictations. Your dictionary and history stay.",
            control: .removal(
                SettingsRemoval(
                    reset: .persona, title: "Reset…",
                    confirmation: SettingsConfirmation(
                        title: "Reset what Uttrflow noticed?",
                        message:
                            "This removes \(count) Uttrflow noticed from your dictations. "
                            + "Your dictionary and history stay. This cannot be undone.",
                        confirmTitle: "Reset", cancelTitle: "Cancel"))),
            unavailability: SettingsEditor.unavailability(of: .persona, given: personalisation),
            icon: .symbol("person.crop.circle", .amber))
        return SettingsGroup(id: "persona", title: "What Uttrflow noticed about you", rows: [reset] + items)
    }

    // MARK: - Rows

    /// A switch row, taking its reason for being off from the ``SettingsEditor`` that refuses it.
    static func toggleRow(
        _ field: SettingsToggleField,
        label: String,
        explanation: String? = nil,
        _ settings: Settings,
        _ capabilities: SettingsCapabilities
    ) -> SettingsRow {
        let isOn = value(of: field, in: settings)
        return SettingsRow(
            id: field.rawValue,
            label: label,
            explanation: explanation,
            control: .toggle(field: field, isOn: isOn),
            unavailability: SettingsEditor.unavailability(
                of: field, given: capabilities, in: settings))
    }

    /// Where a switch reads its state from, in the one place that knows.
    static func value(of field: SettingsToggleField, in settings: Settings) -> Bool {
        switch field {
        case .dictationEnabled: settings.dictationEnabled
        case .handsFreeEnabled: settings.handsFreeEnabled
        case .clipboardEnabled: settings.clipboardEnabled
        case .showsFloatingButton: settings.showsFloatingButton
        case .shrinksToGripWhenIdle: settings.shrinksToGripWhenIdle
        case .minimisesWhileDictating: settings.minimisesWhileDictating
        case .playsSoundWhenRecordingStarts: settings.playsSoundWhenRecordingStarts
        case .opensAtLogin: settings.opensAtLogin
        case .checksForUpdatesAutomatically: settings.checksForUpdatesAutomatically
        case .installsUpdatesAutomatically: settings.installsUpdatesAutomatically
        case .sharesUsageStatistics: settings.sharesUsageStatistics
        case .sendsCrashReports: settings.sendsCrashReports
        case .suggestionsEnabled: settings.suggestions.isEnabled
        case .quietSuggestions: settings.suggestions.isQuiet
        case .learnsFromDictation: settings.learnsFromDictation
        case .confirmsHiddenClipPaste: settings.confirmsHiddenClipPaste
        }
    }
}
