extension AppDelegate {
    func suggestionTurnedOffHandler() -> () -> Void {
        { [weak self] in self?.apply(.toggle(.suggestionsEnabled, isOn: false)) }
    }

    func suggestionConsentPersistenceFailureHandler() -> ((any Error) -> Void) {
        { [weak self] error in
            self?.report(error)
            self?.refreshMainWindow()
        }
    }
}
