// Builds the global and per-application context-level settings metadata.
import UttrflowCore
import UttrflowSettings

extension SettingsPresenter {
    /// What each context level is called in its menu.
    static func title(of level: ContextLevel) -> String {
        switch level {
        case .identity: "App name only"
        case .nearCaret: "Text near the cursor"
        }
    }

    /// How much of the app in front a dictation reads: its name only, or the text around the cursor too.
    static func contextLevelRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "contextLevel",
            label: "What dictation reads",
            explanation: settings.contextLevel == .identity
                ? "Only the name of the app you dictate into. Formatting falls back to its defaults."
                : "The app's name, its window title and the text around your cursor, to format your words.",
            control: .segmented(
                options: ContextLevel.allCases.map { level in
                    SettingsOption(id: level.rawValue, title: title(of: level), change: .contextLevel(level))
                },
                selectedID: settings.contextLevel.rawValue),
            icon: .symbol("eye", .info))
    }

    /// The level every application gets, then each application with its own, then a way to add one.
    static func contextRows(_ settings: Settings) -> [SettingsRow] {
        [contextLevelRow(settings)]
            + settings.contextLevelOverrides.overrides.map {
                contextLevelRow(for: $0, every: settings.contextLevel)
            }
            + [addContextLevelAppRow]
    }

    /// One application's own level, and the option that puts it back on the level every application gets.
    static func contextLevelRow(for override: ContextLevelOverride, every level: ContextLevel) -> SettingsRow
    {
        let everyApp = SettingsOption(
            id: everyAppContextLevelID, title: "Same as every app (\(title(of: level)))",
            change: .forgetAppContextLevel(bundleIdentifier: override.bundleIdentifier))
        return SettingsRow(
            id: "contextApp-\(override.id)",
            label: override.title,
            explanation: override.level == .identity
                ? "Only this app's name is read."
                : "This app's window title and the text around your cursor are read.",
            control: .menu(
                options: [everyApp]
                    + ContextLevel.allCases.map { offered in
                        SettingsOption(
                            id: offered.rawValue, title: title(of: offered),
                            change: .appContextLevel(
                                bundleIdentifier: override.bundleIdentifier, name: override.applicationName,
                                level: offered))
                    },
                selectedID: override.level.rawValue),
            icon: .application(bundleIdentifier: override.bundleIdentifier, name: override.title))
    }

    /// The menu option that removes an application's own level.
    static let everyAppContextLevelID = "everyApp"

    /// Asks for an installed application, so it can be read at a level of its own.
    static let addContextLevelAppRow = SettingsRow(
        id: "addContextApp",
        label: "Set an app apart",
        control: .action(title: "Add an app", change: .chooseApplicationForContextLevel),
        style: .add)

    /// The change that stores a picked application as read by name only, the least it can be read.
    public static func addingContextLevelApp(_ app: SettingsApp) -> SettingsChange {
        .appContextLevel(bundleIdentifier: app.bundleIdentifier, name: app.name, level: .identity)
    }

}
