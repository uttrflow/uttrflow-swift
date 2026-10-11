import Foundation

private struct SuggestionSessionEndObservers {
    let workspaceCenter: NotificationCenter
    let workspaceObservers: [any NSObjectProtocol]
    let screenLockCenter: NotificationCenter
    let screenLockObserver: any NSObjectProtocol

    func remove() {
        for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
        screenLockCenter.removeObserver(screenLockObserver)
    }
}

/// Holds every notification registration the loop owns, while its caller keeps callback policy and removal order.
@MainActor
final class SuggestionNotificationObservations {
    private var activations: (any NSObjectProtocol)?
    private var sessionEndObservers: SuggestionSessionEndObservers?
    /// The Space and sleep observers, each of which leaves a ghost with no field under it.
    private var spaceObservers: [any NSObjectProtocol] = []
    /// Withdraws the ghost when a display is unplugged or rearranged while the Mac stays awake.
    private var screenChangeObserver: (center: NotificationCenter, token: any NSObjectProtocol)?

    func observeActivations(creating create: () -> any NSObjectProtocol) {
        activations = create()
    }

    func observeSpace(creating create: () -> any NSObjectProtocol) {
        spaceObservers.append(create())
    }

    func observeScreen(in center: NotificationCenter, creating create: () -> any NSObjectProtocol) {
        guard screenChangeObserver == nil else { return }
        let token = create()
        screenChangeObserver = (center, token)
    }

    func observeSessionEnd(
        in workspaceCenter: NotificationCenter, screenLockCenter: NotificationCenter,
        creating create: () -> (@Sendable () -> Void)
    ) {
        guard sessionEndObservers == nil else { return }
        let onEnd = create()
        sessionEndObservers = SuggestionSessionEndObservers(
            workspaceCenter: workspaceCenter,
            workspaceObservers: DictationSessionEndObserver.observe(in: workspaceCenter, onEnd: onEnd),
            screenLockCenter: screenLockCenter,
            screenLockObserver: DictationSessionEndObserver.observeScreenLock(
                in: screenLockCenter, onEnd: onEnd))
    }

    func removeActivations(from workspaceCenter: NotificationCenter) {
        if let activations { workspaceCenter.removeObserver(activations) }
        activations = nil
    }

    func removeSessionEnd() {
        sessionEndObservers?.remove()
        sessionEndObservers = nil
    }

    func removeSpaces(from workspaceCenter: NotificationCenter) {
        for observer in spaceObservers { workspaceCenter.removeObserver(observer) }
        spaceObservers = []
    }

    func removeScreen() {
        if let screenChangeObserver { screenChangeObserver.center.removeObserver(screenChangeObserver.token) }
        screenChangeObserver = nil
    }
}
