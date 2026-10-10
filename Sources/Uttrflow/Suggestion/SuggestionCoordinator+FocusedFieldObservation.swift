import AppKit
import UttrflowPredict

@MainActor
extension SuggestionCoordinator {
    /// Whether the foreground application can run the suggestion loop now.
    func activityIsAllowed() -> Bool {
        Self.shouldProcessActivityEvent(
            front: frontmostBundleIdentifier(),
            own: ownBundleIdentifier, preferences: preferences, at: Date())
    }

    /// Points the value observer at the front application, or at nothing where suggestions are off; never waits on it.
    func refreshFocusedFieldObservation() {
        focusedFieldValueObserver.refresh(for: focusedFieldObservationTarget())
    }

    /// The front application the observer may contact, or nil where suggestions are off.
    func focusedFieldObservationTarget() -> FocusedFieldObservationTarget? {
        Self.focusedFieldObservationTarget(
            processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            bundleIdentifier: frontmostBundleIdentifier(),
            ownBundleIdentifier: ownBundleIdentifier,
            preferences: preferences,
            at: Date())
    }

    nonisolated static func focusedFieldObservationTarget(
        processIdentifier: pid_t?, bundleIdentifier: String?, ownBundleIdentifier: String?,
        preferences: SuggestionPreferences, at moment: Date
    ) -> FocusedFieldObservationTarget? {
        guard let processIdentifier,
            shouldProcessActivityEvent(
                front: bundleIdentifier, own: ownBundleIdentifier, preferences: preferences, at: moment),
            let bundleIdentifier
        else { return nil }
        return FocusedFieldObservationTarget(
            processIdentifier: processIdentifier, bundleIdentifier: bundleIdentifier)
    }
}
