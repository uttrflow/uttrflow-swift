import UttrflowSettings

extension SettingsPresenter {
    /// The order the theme is offered in: following the Mac first, then the two fixed looks.
    static let offeredAppearances: [AppAppearance] = [.system, .light, .dark]

    /// What a theme is called on the segmented control.
    static func title(of appearance: AppAppearance) -> String {
        switch appearance {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Light, dark, or the same as the Mac.
    static func appearanceRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "appearance",
            label: "Theme",
            explanation:
                "Uttrflow is drawn dark unless you would rather have it light, or the same as your Mac.",
            control: .segmented(
                options: offeredAppearances.map { offered in
                    SettingsOption(
                        id: offered.rawValue, title: title(of: offered), change: .appearance(offered))
                },
                selectedID: settings.appearance.rawValue),
            icon: .symbol("moon", .suggestion))
    }
}
