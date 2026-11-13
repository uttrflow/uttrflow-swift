// Builds the rows that choose which dictations History keeps: none at all, or none from chosen apps.
import UttrflowPredict
import UttrflowSettings

extension SettingsPresenter {
    /// The switch that keeps no dictation text, then each app left out of History, then a way to add one.
    static func historyKeepingRows(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> [SettingsRow] {
        let keepsNothing = toggleRow(
            .keepsNoTranscripts,
            label: "Keep no dictation text",
            explanation: "On, every dictation is typed and then left out of History, in every app.",
            settings, capabilities
        ).with(icon: .symbol("text.badge.xmark", .neutral))
        return [keepsNothing] + settings.historyExcludedApplications.map(excludedFromHistoryRow)
            + [addHistoryExclusionRow]
    }

    /// One app whose dictations History leaves out, and the button that keeps them again.
    static func excludedFromHistoryRow(_ bundleIdentifier: String) -> SettingsRow {
        let name = SuggestionApplications.name(of: bundleIdentifier)
        return SettingsRow(
            id: "historyExcluded.\(bundleIdentifier.lowercased())",
            label: name,
            explanation: "Dictations here are typed and then left out of History.",
            control: .action(
                title: "Remove", change: .keepsHistory(application: bundleIdentifier, isOn: true)),
            icon: .application(bundleIdentifier: bundleIdentifier, name: name))
    }

    /// Asks for an installed application whose dictations History should leave out.
    static let addHistoryExclusionRow = SettingsRow(
        id: "addHistoryExclusion",
        label: "Leave an app out of History",
        control: .action(title: "Add an app", change: .chooseApplicationToKeepNoHistory),
        style: .add)
}
