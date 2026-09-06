import Foundation
import Synchronization

public import UttrflowCore

/// Watches for the chosen shortcut through one source and one recogniser. See `Docs/shortcuts.md`.
public final class ActivationMonitor: HotkeyMonitoring {
    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let source: any KeyboardEventSource
    private let recogniser = Mutex<HotkeyRecogniser?>(nil)

    /// Takes the source it listens through, so a test can hand it strokes instead of a keyboard.
    public init(source: any KeyboardEventSource = SystemKeyboard()) {
        self.source = source
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        source.stop()
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
            try source.start { [weak self] stroke in
                let happened = self?.recogniser.withLock { $0?.receive(stroke) } ?? nil
                if let happened {
                    continuation.yield(happened)
                }
            }
        } catch {
            throw .observationNotPermitted
        }
    }

    public func stop() {
        source.stop()
        // A hold interrupted by stopping is a release, or the microphone stays open.
        let owed = recogniser.withLock { current -> HotkeyEvent? in
            defer { current = nil }
            return current?.finish()
        }
        if let owed { continuation.yield(owed) }
    }
}
