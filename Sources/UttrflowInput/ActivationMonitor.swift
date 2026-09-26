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
    /// Set for the duration of `stop()`, so a release it triggers cannot call back into it.
    private let stopping = Atomic<Bool>(false)

    /// Takes the source it listens through, so a test can hand it strokes instead of a keyboard.
    public convenience init(source: any KeyboardEventSource = SystemKeyboard()) {
        self.init(source: source, strokeLeftLock: {})
    }

    init(source: any KeyboardEventSource, strokeLeftLock: @escaping @Sendable () -> Void) {
        self.source = source
        self.strokeLeftLock = strokeLeftLock
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // Not `source.stop()`: a source this monitor owns stops itself, and reaching out here recurses.
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
                    recogniser.withLock { current in
                        if let happened = current?.receive(stroke) { continuation.yield(happened) }
                    }
                    strokeLeftLock()
                }, consumeKeyDown: false)
        } catch {
            throw .observationNotPermitted
        }
    }

    public func stop() {
        guard stopping.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged
        else { return }
        defer { stopping.store(false, ordering: .relaxed) }
        source.stop()
        // A hold interrupted by stopping is a release, or the microphone stays open.
        recogniser.withLock { current in
            if let owed = current?.finish() { continuation.yield(owed) }
            current = nil
        }
    }
}
