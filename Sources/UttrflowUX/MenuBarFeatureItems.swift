extension MenuBarPresenter {
    /// The three switches, always all three, so turning one off never hides another.
    static func featureItems(
        for features: MenuBarFeatures, suggestionModel: SuggestionModelReadiness = .notAsked
    ) -> [MenuBarItem] {
        [.sectionHeader("Turn on and off")]
            + MenuBarFeature.allCases.map { feature in
                let isOn = features.isOn(feature)
                let hold = feature == .suggestions && !isOn ? features.suggestionHold : nil
                return .command(
                    MenuBarCommand(
                        title: title(of: feature, isOn: isOn, suggestionModel: suggestionModel, hold: hold),
                        intent: hold.map(intent(lifting:)) ?? .setFeature(feature, isOn: !isOn),
                        isChecked: isOn))
            }
    }

    /// The same edits Settings makes to lift a hold, or Settings itself for an application that ships off.
    static func intent(lifting hold: SuggestionHold) -> MenuBarIntent {
        switch hold {
        case .paused:
            return .changeSettings([.pauseSuggestions(isOn: false)])
        case .turnedOffHere(let application, let isPaused):
            let here = SettingsChange.suggestionsHere(application: application, isOn: true)
            return .changeSettings(isPaused ? [.pauseSuggestions(isOn: false), here] : [here])
        case .offByDefault, .offAsPrivate:
            return .open(.settings(.suggestions))
        }
    }

    /// A switch's name, followed for AI suggestions by what their model is waiting on or what holds them off.
    static func title(
        of feature: MenuBarFeature, isOn: Bool, suggestionModel: SuggestionModelReadiness,
        hold: SuggestionHold? = nil
    ) -> String {
        let name = feature.isBeta ? "\(feature.title), \(BetaFeature.label)" : feature.title
        guard feature == .suggestions else { return name }
        if let hold { return "\(name) — \(holdLine(hold))" }
        guard isOn, let headline = suggestionModel.headline else { return name }
        return "\(name) — \(headline)"
    }

    /// What holds suggestions off, and what choosing the item will do about it.
    private static func holdLine(_ hold: SuggestionHold) -> String {
        switch hold {
        case .paused: "Paused, click to resume"
        case .turnedOffHere(_, isPaused: false): "Off in this app, click to turn on"
        case .turnedOffHere(_, isPaused: true): "Paused and off in this app, click to turn on"
        case .offByDefault: "Off in this app, which has its own suggestions; open Settings…"
        case .offAsPrivate: "Off in this app, which holds private information; open Settings…"
        }
    }
}
