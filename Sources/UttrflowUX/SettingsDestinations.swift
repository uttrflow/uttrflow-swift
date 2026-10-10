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

/// An app no table row names, so its dictations went in as plain text by default rather than by decision.
public struct PlainTextApp: Sendable, Equatable {
    public let app: SettingsApp
    /// How many kept dictations went into it.
    public let dictations: Int

    public init(app: SettingsApp, dictations: Int) {
        self.app = app
        self.dictations = dictations
    }
}

/// What each kind of place is called on screen.
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
        case .terminal: "A terminal"
        case .messaging: "A chat"
        case .email: "An email"
        case .plain: "Plain text"
        }
    }

    /// The same name inside a sentence, so "A SQL editor" reads "a SQL editor" rather than "a sql editor".
    public static func phrase(of destination: UttrflowCore.Destination) -> String {
        let name = title(of: destination)
        guard let first = name.first else { return name }
        return first.lowercased() + name.dropFirst()
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

    /// The override rows: apps in kept history newest first, then other overrides, then a way to add an app.
    public static func places(
        _ overrides: DestinationOverrides, recentApps: [SettingsApp]
    ) -> SettingsGroup {
        let (listed, historyCount) = apps(recentApps, overrides)
        let rows =
            listed.isEmpty
            ? [nothingYetRow]
            : listed.enumerated().map { index, app in
                appRow(
                    app, overrides, explanation: explanation(at: index, fromHistory: index < historyCount))
            }
        return SettingsGroup(id: "places", title: "Where your words go", rows: rows + [addAppRow])
    }

    /// History's apps in the order given, then overrides with no history in their own stable order, one per key.
    static func apps(
        _ recent: [SettingsApp], _ overrides: DestinationOverrides
    ) -> (apps: [SettingsApp], historyCount: Int) {
        var seen: Set<String> = []
        let fromHistory = recent.filter { seen.insert(ApplicationKey.of($0.bundleIdentifier)).inserted }
            .map { app in
                let saved = overrides.overrides.first { $0.id == ApplicationKey.of(app.bundleIdentifier) }
                return SettingsApp(
                    bundleIdentifier: app.bundleIdentifier, name: app.name ?? saved?.applicationName)
            }
        let fromOverrides = overrides.overrides.filter { seen.insert($0.id).inserted }
            .map { SettingsApp(bundleIdentifier: $0.bundleIdentifier, name: $0.applicationName) }
        return (fromHistory + fromOverrides, fromHistory.count)
    }

    /// How many fallen-through apps the list names; the rest are the long tail of rarely used apps.
    static let plainTextAppsShown = 10

    /// The apps that fell through to plain text and have no override, each with the same pop-up as the last app.
    public static func plainTextApps(
        _ apps: [PlainTextApp], overrides: DestinationOverrides
    ) -> SettingsGroup? {
        let unassigned = apps.filter {
            overrides.destination(forBundleIdentifier: $0.app.bundleIdentifier) == nil
        }
        guard !unassigned.isEmpty else { return nil }
        return SettingsGroup(
            id: "plainTextApps", title: "Apps written as plain text",
            rows: unassigned.prefix(plainTextAppsShown).map(plainTextAppRow))
    }

    static func plainTextAppRow(_ entry: PlainTextApp) -> SettingsRow {
        let app = entry.app
        let automatic = SettingsOption(
            id: automaticID, title: automaticTitle,
            change: .forgetAppDestination(bundleIdentifier: app.bundleIdentifier))
        let dictations = entry.dictations == 1 ? "1 dictation" : "\(entry.dictations) dictations"
        return SettingsRow(
            id: "plain-\(ApplicationKey.of(app.bundleIdentifier))",
            label: app.title,
            explanation:
                "No rule names this app, so \(dictations) went in as plain text. "
                + "Choose what kind of place it is.",
            control: .menu(
                options: [automatic] + offered.map { option(for: $0, in: app) },
                selectedID: automaticID),
            icon: .application(bundleIdentifier: app.bundleIdentifier, name: app.title))
    }

    private static func explanation(at index: Int, fromHistory: Bool) -> String {
        guard fromHistory else { return "Kept from a choice you made." }
        return index == 0
            ? "The last app you dictated into. Uttrflow writes to suit the place."
            : "An app you dictated into recently."
    }

    /// Before anything is dictated or chosen there is no app to have a choice about.
    static let nothingYetRow = SettingsRow(
        id: "lastApp",
        label: "The app you dictate into",
        explanation:
            "Dictate somewhere once and it appears here, so you can say what kind of place it is.",
        control: .placeholder("Nothing yet"),
        icon: .symbol("macbook", .neutral))

    /// Asks for an installed app, so one can be set before it is ever dictated into.
    static let addAppRow = SettingsRow(
        id: "addApp",
        label: "Add an app",
        control: .action(title: "Add an app", change: .chooseApplicationForDestination),
        style: .add)

    /// What the table, not any override, makes of this app; "Work it out" names it.
    public static func automaticDestination(for app: SettingsApp) -> UttrflowCore.Destination {
        DestinationClassifier.classify(
            AppContext(applicationName: app.name, bundleIdentifier: app.bundleIdentifier))
    }

    /// The change that stores a picked app as the table's answer, so it is listed and can then be changed.
    public static func adding(_ app: SettingsApp) -> SettingsChange {
        .appDestination(
            bundleIdentifier: app.bundleIdentifier, name: app.name,
            destination: automaticDestination(for: app))
    }

    /// What Uttrflow treats one app as, and the pop-up for disagreeing with it.
    static func appRow(
        _ app: SettingsApp, _ overrides: DestinationOverrides, explanation: String
    ) -> SettingsRow {
        let chosen = overrides.destination(forBundleIdentifier: app.bundleIdentifier)
        let worked = phrase(of: automaticDestination(for: app))
        let automatic = SettingsOption(
            id: automaticID, title: "\(automaticTitle) (\(worked))",
            change: .forgetAppDestination(bundleIdentifier: app.bundleIdentifier))
        return SettingsRow(
            id: "app-\(ApplicationKey.of(app.bundleIdentifier))",
            label: app.title,
            explanation: explanation,
            control: .menu(
                options: [automatic] + offered.map { option(for: $0, in: app) },
                selectedID: chosen?.rawValue ?? automaticID),
            icon: .application(bundleIdentifier: app.bundleIdentifier, name: app.title))
    }

    static func option(
        for destination: UttrflowCore.Destination, in app: SettingsApp
    ) -> SettingsOption {
        SettingsOption(
            id: destination.rawValue, title: title(of: destination),
            change: .appDestination(
                bundleIdentifier: app.bundleIdentifier, name: app.name, destination: destination))
    }
}
