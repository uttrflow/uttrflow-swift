import ApplicationServices
import UttrflowCore
import UttrflowInput

/// Whether the dictation shortcut is armed, kept apart from any dictation's state. See `Docs/shortcuts.md`.
@MainActor
final class ShortcutArming {
    /// Why the shortcut is not armed, or `nil` when it is.
    private(set) var failure: HotkeyError? {
        didSet { if failure != oldValue { onChange() } }
    }

    /// Told whenever the failure appears, changes or clears, so the lasting surfaces redraw.
    private let onChange: @MainActor () -> Void

    private let accessibilityIsGranted: @MainActor () -> Bool
    private let retryInterval: Duration
    /// Told the first outcome, which is when a launch's shortcut starts being heard or refused.
    private let launch: LaunchMilestone
    /// The loop retrying after Accessibility permission is granted, or `nil` when nothing will retry.
    private(set) var retryTask: Task<Void, Never>?

    init(
        onChange: @escaping @MainActor () -> Void,
        accessibilityIsGranted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        retryInterval: Duration = .seconds(2),
        launch: LaunchMilestone = LaunchMilestone()
    ) {
        self.onChange = onChange
        self.accessibilityIsGranted = accessibilityIsGranted
        self.retryInterval = retryInterval
        self.launch = launch
    }

    /// Arms through `start`, keeping a failure as this state rather than reporting it as a dictation.
    func arm(_ start: @escaping @MainActor () async throws(HotkeyError) -> Void) async {
        do {
            try await start()
            failure = nil
            launch.shortcutSettled(.armed)
            stopRetrying()
        } catch {
            failure = error
            launch.shortcutSettled(.refused)
            if error == .observationNotPermitted {
                retryUntilPermissionGranted(start)
            } else {
                stopRetrying()
            }
        }
    }

    /// Forgets the failure once dictation is off, since an unwatched shortcut owes nobody a notice.
    func disarm() {
        stopRetrying()
        failure = nil
    }

    private func retryUntilPermissionGranted(
        _ start: @escaping @MainActor () async throws(HotkeyError) -> Void
    ) {
        guard retryTask == nil else { return }
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: retryInterval) } catch { return }
                guard !Task.isCancelled else { return }
                guard accessibilityIsGranted() else { continue }
                await arm(start)
                if failure != .observationNotPermitted { return }
            }
        }
    }

    private func stopRetrying() {
        retryTask?.cancel()
        retryTask = nil
    }

    /// What the surfaces say while the shortcut cannot be heard, secure input first since it blocks every shortcut.
    static func unheard(secureInputBlocking: Bool, failure: HotkeyError?) -> String? {
        if secureInputBlocking { return SecureInputWatch.notice }
        return failure?.userMessage
    }
}
