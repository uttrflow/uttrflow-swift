// Builds the rows that name the apps dictation never learns from.
import UttrflowPredict
import UttrflowSettings

extension SettingsPresenter {
    /// One app dictation never learns from, and the button that lets it learn there again.
    static func notLearningFromRow(_ bundleIdentifier: String) -> SettingsRow {
        let name = SuggestionApplications.name(of: bundleIdentifier)
        return SettingsRow(
            id: "learningExcluded.\(bundleIdentifier.lowercased())",
            label: name,
            explanation: "Nothing you dictate here teaches new words.",
            control: .action(
                title: "Remove", change: .learnsInApplication(application: bundleIdentifier, isOn: true)),
            icon: .application(bundleIdentifier: bundleIdentifier, name: name))
    }

    /// Asks for an installed application dictation must never learn from.
    static let addLearningExclusionRow = SettingsRow(
        id: "addLearningExclusion",
        label: "Never learn from an app",
        control: .action(title: "Add an app", change: .chooseApplicationToStopLearning),
        style: .add)
}

extension SettingsChange {
    /// What picking `application` does for a request to choose one: leave it out of History, or stop learning there.
    package func leavingOut(_ application: String) -> SettingsChange {
        switch self {
        case .chooseApplicationToStopLearning: .learnsInApplication(application: application, isOn: false)
        default: .keepsHistory(application: application, isOn: false)
        }
    }
}
