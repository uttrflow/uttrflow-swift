/// Runs potentially blocking observer messages away from the app's main actor.
protocol FocusedFieldAXWorking: Sendable {
    func observe(
        _ target: FocusedFieldObservationTarget?,
        callbackContext: FocusedFieldValueObserverCallbackContext,
        isCurrent: @Sendable () -> Bool)
    func focusedElementChanged(isCurrent: @Sendable () -> Bool)
    func stop()
}
