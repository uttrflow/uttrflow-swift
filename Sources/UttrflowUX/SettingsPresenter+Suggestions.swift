import struct Foundation.Date
import UttrflowCore
import UttrflowPredict
import UttrflowSettings

/// The AI suggestions tab: the switches, the model's state, and the apps suggestions run in or leave alone.
extension SettingsPresenter {
    /// The master switch, the quiet switch and the pause, then where suggestions are left alone.
    static func suggestions(
        _ settings: Settings,
        _ personalisation: SettingsPersonalisation,
        _ capabilities: SettingsCapabilities,
        _ moment: Date
    ) -> SettingsPane {
        SettingsPane(
            tab: .suggestions,
            title: title(of: .suggestions),
            banner: suggestionModelBanner(settings, capabilities),
            groups: [
                SettingsGroup(
                    id: "suggestions",
                    title: "AI suggestions",
                    rows: [
                        toggleRow(
                            .suggestionsEnabled,
                            label: "Turn on AI suggestions",
                            explanation: suggestionsExplanation,
                            settings, .everything
                        ).with(icon: .symbol("power", .suggestion))
                            .with(badge: BetaFeature.label),
                        toggleRow(
                            .quietSuggestions,
                            label: "Only suggest when it is sure",
                            explanation: "Never offers a list to choose between.",
                            settings, .everything
                        ).with(icon: .symbol("bolt", .amber)),
                        pauseRow(settings, moment),
                    ] + (retrySuggestionModelRow(settings, capabilities).map { [$0] } ?? [])),
                applicationGroup(settings, personalisation),
                acceptKeyGroup(settings, personalisation),
            ].compactMap(\.self),
            callout: SettingsCallout(symbolName: "lock", message: suggestionsPromise, tint: .suggestion),
            unavailability: settings.suggestions.isEnabled ? nil : SettingsEditor.suggestionsAreOff)
    }

    /// What switching suggestions on lets Uttrflow read, write and keep.
    static let suggestionsExplanation =
        "Reads the text in and around the field you are typing in, and suggests the rest of the "
        + "line from lines you have sent before, from this Mac, or written by AI that runs on it. "
        + "Remembers the lines you send. Off until you ask for it."

    /// Where suggestions run, where everything they read and keep stays, and where to turn them off or forget them.
    static let suggestionsPromise =
        "Suggestions work in every app except the ones listed. What it reads stays on this Mac. "
        + "The lines it remembers are kept in Uttrflow's own folder. Nothing is uploaded, and "
        + "password, one-time-code, PIN, card security code and recovery-answer fields are never "
        + "read. Turn it off for one application, or forget what it learned there, in the lists above."

    /// Says what the model is doing, since a switch that is on and silent is indistinguishable from broken.
    static func suggestionModelBanner(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsBanner? {
        guard settings.suggestions.isEnabled else { return nil }
        switch capabilities.suggestionRuntime {
        case .starting:
            return SettingsBanner(
                symbolName: "clock", title: "Starting suggestions…",
                message: "Suggestions will be ready shortly.")
        case .tapResting:
            return SettingsBanner(
                symbolName: "clock", title: "Suggestions are paused briefly",
                message: "Suggestions will resume automatically.")
        case .restarting:
            return SettingsBanner(
                symbolName: "clock", title: "Restarting suggestions…",
                message: "Suggestions will resume automatically.")
        case .secureInputBlocked:
            return SettingsBanner(
                symbolName: "lock", title: "Suggestions are paused",
                message: "A secure input field is active. Suggestions resume when you leave it.")
        case .accessibilityDenied:
            return SettingsBanner(
                symbolName: "exclamationmark.triangle",
                title: String(
                    localized: "Accessibility access needed",
                    comment: "Settings banner title when suggestions lack Accessibility permission"),
                message: SuggestionRuntimeStatus.accessibilityDeniedMessage)
        case .tapFailed:
            return SettingsBanner(
                symbolName: "exclamationmark.triangle", title: "Suggestions could not start",
                message:
                    "Allow Uttrflow to monitor input in Privacy & Security, then turn suggestions off and on again."
            )
        case .corpusFailed:
            return SettingsBanner(
                symbolName: "exclamationmark.triangle", title: "Suggestions could not start",
                message:
                    "Uttrflow could not open its saved suggestions file (predict.v1.sqlite). "
                    + "Check that the Uttrflow folder in Application Support is available, then "
                    + "turn suggestions off and on again."
            )
        case .idle, .running:
            break
        }
        // Nothing to explain while the feature is off: the model is not fetched until it is asked for.
        guard let title = capabilities.suggestionModel.headline else { return nil }
        switch capabilities.suggestionModel {
        case .ready, .notAsked, .downloading:
            return SettingsBanner(
                symbolName: "arrow.down.circle",
                title: title,
                message:
                    "Uttrflow is fetching the model that finishes your lines, about 3 GB, once. "
                    + "AI suggestions start when it lands.")
        case .loading:
            return SettingsBanner(
                symbolName: "clock",
                title: title,
                message: "The model is being read into memory for AI suggestions.")
        case .releasedForMemory:
            return SettingsBanner(
                symbolName: "memorychip",
                title: title,
                message:
                    "This Mac is short of memory, so the model that finishes your lines has been "
                    + "set aside. AI suggestions come back on their own once memory frees up.")
        case .fetchFailed, .failed:
            return SettingsBanner(
                symbolName: "exclamationmark.triangle",
                title: title,
                message: "AI suggestions cannot run without it. Check your connection, then try again.")
        case .loadFailed:
            return SettingsBanner(
                symbolName: "exclamationmark.triangle",
                title: title,
                message: "AI suggestions cannot run without it. Try loading it again.")
        }
    }

    /// Offers recovery only after a failed fetch or disk load.
    private static func retrySuggestionModelRow(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsRow? {
        guard settings.suggestions.isEnabled else { return nil }
        let advice: String
        switch capabilities.suggestionModel {
        case .fetchFailed, .failed:
            advice = "Check your connection, then fetch the model again."
        case .loadFailed:
            advice = "Try loading the model again."
        default:
            return nil
        }
        let label =
            capabilities.suggestionModel == .loadFailed
            ? "Suggestion model could not be loaded" : "Suggestion model could not be fetched"
        return SettingsRow(
            id: "retrySuggestionModel", label: label,
            explanation: advice,
            control: .action(title: "Retry", change: .retrySuggestionModel),
            icon: .symbol("arrow.clockwise", .suggestion))
    }

    /// The half-hour pause, which lifts itself and so is a button rather than a switch.
    static func pauseRow(_ settings: Settings, _ moment: Date) -> SettingsRow {
        let remaining = settings.suggestions.pauseRemaining(at: moment)
        return SettingsRow(
            id: "pauseSuggestions",
            label: "Pause for a while",
            explanation: pauseSentence(remaining),
            control: .action(
                title: remaining == nil ? "Pause 30 min" : "Resume",
                change: .pauseSuggestions(isOn: remaining == nil)),
            unavailability: settings.suggestions.isEnabled ? nil : SettingsEditor.suggestionsAreOff,
            icon: .symbol("pause", .mint))
    }

    /// What a running pause has left, rounded up so a pause never reads as "0 minutes left".
    static func pauseSentence(_ remaining: Double?) -> String {
        guard let remaining else {
            return "Stops for 30 minutes, then comes back on its own."
        }
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        return "Paused. Comes back on its own in \(counted(minutes, "minute", "minutes"))."
    }

    /// Every application suggestions are off in, each with the button that turns them back on.
    static func applicationGroup(
        _ settings: Settings, _ personalisation: SettingsPersonalisation
    ) -> SettingsGroup {
        let preferences = settings.suggestions
        let rows =
            preferences
            .knownApplications(learnedIn: personalisation.applicationsWithSuggestions)
            .filter { !preferences.state(of: $0.bundleIdentifier).isOn }
            .flatMap { application in
                [offApplicationRow(application, preferences, settings)]
                    + forgetRows(application, personalisation)
            }
        return SettingsGroup(
            id: "suggestionApplications", title: "Not used in these apps",
            rows: rows + [addApplicationRow(settings)])
    }

    /// Every application suggestions run in that has a choice or a corpus to show, or nothing when none has.
    static func acceptKeyGroup(
        _ settings: Settings, _ personalisation: SettingsPersonalisation
    ) -> SettingsGroup? {
        let preferences = settings.suggestions
        let off = settings.suggestions.isEnabled ? nil : SettingsEditor.suggestionsAreOff
        let rows =
            preferences
            .knownApplications(learnedIn: personalisation.applicationsWithSuggestions)
            .filter { preferences.state(of: $0.bundleIdentifier).isOn }
            .flatMap { application in
                [
                    onApplicationRow(application, unavailability: off),
                    acceptKeyRow(application, preferences, unavailability: off),
                ] + forgetRows(application, personalisation)
            }
        guard !rows.isEmpty else { return nil }
        return SettingsGroup(id: "suggestionKeys", title: "Used in these apps", rows: rows)
    }

    /// One application suggestions run in, and the button that leaves it alone from now on.
    private static func onApplicationRow(
        _ application: SuggestionApplication, unavailability: String?
    ) -> SettingsRow {
        let identifier = application.bundleIdentifier
        return SettingsRow(
            id: "suggestionsIn.\(identifier)",
            label: application.name,
            control: .action(
                title: "Leave Alone", change: .suggestionsHere(application: identifier, isOn: false)),
            unavailability: unavailability,
            icon: .application(bundleIdentifier: identifier, name: application.name))
    }

    /// Turns suggestions off in an application before anything has been drawn or learned there.
    static func addApplicationRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "addSuggestionApplication",
            label: "Add an app to leave alone",
            control: .action(
                title: "Add an app to leave alone", change: .chooseApplicationToTurnOffSuggestions),
            unavailability: settings.suggestions.isEnabled ? nil : SettingsEditor.suggestionsAreOff,
            style: .add)
    }

    /// One application suggestions are off in, and the button that takes it off the list.
    private static func offApplicationRow(
        _ application: SuggestionApplication,
        _ preferences: SuggestionPreferences,
        _ settings: Settings
    ) -> SettingsRow {
        let identifier = application.bundleIdentifier
        let title = SuggestionApplications.isOffByDefault(identifier) ? "Turn on" : "Remove"
        return SettingsRow(
            id: "suggestionsIn.\(identifier)",
            label: application.name,
            explanation: applicationSentence(preferences.state(of: identifier)),
            control: .action(
                title: title, change: .suggestionsHere(application: identifier, isOn: true)),
            unavailability: settings.suggestions.isEnabled ? nil : SettingsEditor.suggestionsAreOff,
            icon: .application(bundleIdentifier: identifier, name: application.name))
    }

    /// The forget row for an application that has taught something, or nothing.
    private static func forgetRows(
        _ application: SuggestionApplication, _ personalisation: SettingsPersonalisation
    ) -> [SettingsRow] {
        personalisation.suggestions(from: application.bundleIdentifier) > 0
            ? [forgetSuggestionsRow(application, personalisation)] : []
    }

    /// Why an application is off, said only when the reason is not the user's own choice.
    static func applicationSentence(_ state: SuggestionApplicationState) -> String? {
        switch state {
        case .on: nil
        case .turnedOff: "You turned AI suggestions off here."
        case .offByDefault: "Off here by default (it has its own suggestions)"
        case .offAsPrivate: "Off here by default (it holds private information)"
        }
    }

    /// Which key takes a completion here, since Tab is spoken for in terminals and editors.
    private static func acceptKeyRow(
        _ application: SuggestionApplication,
        _ preferences: SuggestionPreferences,
        unavailability: String?
    ) -> SettingsRow {
        let identifier = application.bundleIdentifier
        let key = preferences.acceptKeys.key(forBundleIdentifier: identifier)
        let kind = DestinationClassifier.kind(for: AppContext(bundleIdentifier: identifier))
        return SettingsRow(
            id: "suggestionAcceptKey.\(identifier)",
            label: "Accept with, \(application.name)",
            explanation: key.explanation(for: kind),
            control: .menu(
                options: AcceptKey.allCases.map { offered in
                    SettingsOption(
                        id: offered.rawValue, title: offered.title,
                        change: .suggestionAcceptKey(application: identifier, key: offered))
                },
                selectedID: key.rawValue),
            unavailability: unavailability,
            style: .inset)
    }

    /// The fifth level: everything one application taught, counted before it is taken.
    private static func forgetSuggestionsRow(
        _ application: SuggestionApplication,
        _ personalisation: SettingsPersonalisation
    ) -> SettingsRow {
        let reset = SettingsReset.suggestions(inApplication: application.bundleIdentifier)
        let learned = personalisation.suggestions(from: application.bundleIdentifier)
        return SettingsRow(
            id: "forgetSuggestions.\(application.bundleIdentifier)",
            label: "Forget what it learned here",
            explanation:
                "Forget \(counted(learned, "completion", "completions")) from "
                + "\(application.name). Everywhere else is untouched.",
            control: .removal(
                SettingsRemoval(
                    reset: reset, title: "Forget…",
                    confirmation: SettingsConfirmation(
                        title: "Forget learned completions?",
                        message:
                            "This removes \(counted(learned, "completion", "completions")) from \(application.name). This cannot be undone.",
                        confirmTitle: "Forget", cancelTitle: "Cancel"))),
            unavailability: SettingsEditor.unavailability(of: reset, given: personalisation),
            style: .inset)
    }
}
