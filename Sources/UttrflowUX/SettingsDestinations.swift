public import UttrflowCore

/// An app the user has dictated into, so a setting can be about it by name.
public struct SettingsApp: Sendable, Equatable {
    public let bundleIdentifier: String
    /// What the screen called it; the identifier stands in when the screen said nothing.
    public let name: String?

    public init(bundleIdentifier: String, name: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    public var title: String {
        guard let name, !name.isEmpty else { return bundleIdentifier }
        return name
    }
}

/// What each kind of place is called on screen; `UttrflowCore.Destination` is written out because this module has its own.
public enum SettingsDestinations {
    /// Every kind, in the order the pop-up lists them.
    public static let offered: [UttrflowCore.Destination] = UttrflowCore.Destination.allCases

    /// Plain words for a kind of place, never the name of an app that is one.
    public static func title(of destination: UttrflowCore.Destination) -> String {
        switch destination {
        case .document: "A document"
        case .spreadsheet: "A spreadsheet cell"
        case .sqlEditor: "A SQL editor"
        case .codeEditor: "Code"
        case .messaging: "A chat"
        case .email: "An email"
        case .plain: "Plain text"
        }
    }

    /// The option that puts an app back on the table Uttrflow ships with.
    public static let automaticID = "automatic"
    static let automaticTitle = "Work it out"

    /// The rows offering the clean-up steps, one tick each, in the order they run.
    public static func steps(_ steps: CleaningSteps) -> SettingsGroup {
        SettingsGroup(
            id: "cleaningSteps",
            title: "Clean-up steps",
            rows: CleaningSteps.offered.map { step in
                let isOn = steps.runs(step.id)
                return SettingsRow(
                    id: "step-\(step.id.rawValue)",
                    label: step.name,
                    explanation: step.detail,
                    control: .tick(
                        isTicked: isOn, change: .cleaningStep(step.id, isOn: !isOn)))
            })
    }

    /// The rows for overriding where the words go: the app last dictated into, then every override made.
    public static func places(
        _ overrides: DestinationOverrides, lastApp: SettingsApp?
    ) -> SettingsGroup {
        SettingsGroup(
            id: "places", title: "Where your words go",
            rows: [lastAppRow(overrides, lastApp)] + overrides.overrides.map(overrideRow))
    }

    /// What Uttrflow treats the last app as, and the pop-up for disagreeing with it.
    static func lastAppRow(
        _ overrides: DestinationOverrides, _ lastApp: SettingsApp?
    ) -> SettingsRow {
        guard let lastApp else {
            return SettingsRow(
                id: "lastApp",
                label: "The app you dictate into",
                explanation:
                    "Dictate somewhere once and it appears here, so you can say what kind of "
                    + "place it is.",
                control: .text("Nothing yet"))
        }

        let chosen = overrides.destination(forBundleIdentifier: lastApp.bundleIdentifier)
        let automatic = SettingsOption(
            id: automaticID, title: automaticTitle,
            change: .forgetAppDestination(bundleIdentifier: lastApp.bundleIdentifier))
        return SettingsRow(
            id: "lastApp",
            label: lastApp.title,
            explanation: "The last app you dictated into. Uttrflow writes to suit the place.",
            control: .menu(
                options: [automatic] + offered.map { option(for: $0, in: lastApp) },
                selectedID: chosen?.rawValue ?? automaticID))
    }

    static func option(
        for destination: UttrflowCore.Destination, in app: SettingsApp
    ) -> SettingsOption {
        SettingsOption(
            id: destination.rawValue, title: title(of: destination),
            change: .appDestination(
                bundleIdentifier: app.bundleIdentifier, name: app.name, destination: destination))
    }

    /// One override the user has made, and the button that puts it back.
    static func overrideRow(_ override: DestinationOverride) -> SettingsRow {
        SettingsRow(
            id: "override-\(override.id)",
            label: override.title,
            explanation: "Treated as \(title(of: override.destination).lowercased()).",
            control: .action(
                title: "Use the Default",
                change: .forgetAppDestination(bundleIdentifier: override.bundleIdentifier)))
    }
}
