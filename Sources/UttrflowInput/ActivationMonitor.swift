import Dispatch
import Foundation
import Synchronization

public import UttrflowCore

/// Watches for the chosen shortcut through one source and one recogniser. See `Docs/shortcuts.md`.
public final class ActivationMonitor: HotkeyMonitoring {
    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let source: any KeyboardEventSource
    private let recogniser = Mutex<HotkeyRecogniser?>(nil)
    /// Runs on the source's thread once a stroke has left the lock, so a test can hold it there.
    private let strokeLeftLock: @Sendable () -> Void
    /// Reads the real keyboard state, so a release the tap never delivers is still noticed.
    private let keyState: any RealKeyStateReading
    /// The timer comparing the real key state against what the recogniser was last told.
    private let reconciliation = Mutex<(any DispatchSourceTimer)?>(nil)
    /// How often that comparison runs, in milliseconds. See `Docs/stuck-recording.md`.
    private static let reconciliationMilliseconds = 250

    /// Takes the source it listens through, so a test can hand it strokes instead of a keyboard.
    public convenience init(source: any KeyboardEventSource = SystemKeyboard()) {
        self.init(source: source, keyState: SystemKeyState(), strokeLeftLock: {})
    }

    init(
        source: any KeyboardEventSource, keyState: any RealKeyStateReading = SystemKeyState(),
        strokeLeftLock: @escaping @Sendable () -> Void
    ) {
        self.source = source
        self.keyState = keyState
        self.strokeLeftLock = strokeLeftLock
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // Not `source.stop()`: a source this monitor owns stops itself, and reaching out here recurses.
        reconciliation.withLock { $0?.cancel() }
        continuation.finish()
    }

    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        stop()
        guard binding.isDeliverable else {
            throw .shortcutUnavailable
        }
        recogniser.withLock { $0 = HotkeyRecogniser(binding: binding) }
        let continuation = continuation
        do {
            try source.start(
                { [weak self] stroke in
                    guard let self else { return }
                    // Yielded under the lock, so a stop's owed release cannot overtake the press it ends.
                    let happened = recogniser.withLock { current -> HotkeyEvent? in
                        let happened = current?.receive(stroke)
                        if let happened { continuation.yield(happened) }
                        return happened
                    }
                    if let happened {
                        switch happened {
                        case .pressed: startReconciling(binding)
                        case .released, .cancelled: stopReconciling()
                        }
                    }
                    strokeLeftLock()
                }, consumeKeyDown: false)
        } catch {
            throw .observationNotPermitted
        }
    }

    public func stop() {
        source.stop()
        stopReconciling()
        // A hold interrupted by stopping is a release, or the microphone stays open.
        recogniser.withLock { current in
            if let owed = current?.finish() { continuation.yield(owed) }
            current = nil
        }
    }

    // MARK: Reconciliation

    /// Reads the real key state, so a release the tap never delivers is still noticed. See `Docs/stuck-recording.md`.
    private func startReconciling(_ binding: HotkeyBinding) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Self.reconciliationMilliseconds),
            repeating: .milliseconds(Self.reconciliationMilliseconds))
        timer.setEventHandler { [weak self] in
            // A monitor released mid-hold cancels its own timer rather than firing for ever.
            guard let self else { timer.cancel(); return }
            guard recogniser.withLock({ $0?.isDown }) == true else { return }
            guard !keyState.isDown(binding) else { return }
            deliverReconciledRelease()
        }
        timer.resume()
        reconciliation.withLock { existing in
            existing?.cancel()
            existing = timer
        }
    }

    private func stopReconciling() {
        reconciliation.withLock { timer in
            timer?.cancel()
            timer = nil
        }
    }

    /// Delivers the release the poll found, the same way an owed release from `stop()` is delivered.
    private func deliverReconciledRelease() {
        let owed = recogniser.withLock { current in current?.finish() }
        guard let owed else { return }
        continuation.yield(owed)
        stopReconciling()
    }
}
