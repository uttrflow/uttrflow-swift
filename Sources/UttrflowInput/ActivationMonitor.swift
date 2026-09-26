import Foundation
import Synchronization

public import UttrflowCore
private import OSLog

/// Watches for the chosen shortcut through one source and one recogniser. See `Docs/shortcuts.md`.
public final class ActivationMonitor: HotkeyMonitoring {
    /// Where a tap giving up for good, and its rebuild, are said, so the failure leaves a trace.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "shortcuts")

    /// How long the source rests before a rebuild, past the window in which disables count against it.
    private static let defaultRestSeconds = 90

    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let source: any KeyboardEventSource
    private let recogniser = Mutex<HotkeyRecogniser?>(nil)
    /// The binding to rebuild with, kept only for the source's own give-up-and-rebuild recovery.
    private let activeBinding = Mutex<HotkeyBinding?>(nil)
    /// The pending rebuild, cancelled by a `stop()` so it never resurrects a shortcut that was deliberately turned off.
    private let rebuild = Mutex<Task<Void, Never>?>(nil)
    /// Runs on the source's thread once a stroke has left the lock, so a test can hold it there.
    private let strokeLeftLock: @Sendable () -> Void
    /// How long a give-up waits before rebuilding, overridable so a test need not wait `restSeconds`.
    private let restSeconds: Int

    /// Takes the source it listens through, so a test can hand it strokes instead of a keyboard.
    public convenience init(source: any KeyboardEventSource = SystemKeyboard()) {
        self.init(source: source, strokeLeftLock: {})
    }

    init(
        source: any KeyboardEventSource, strokeLeftLock: @escaping @Sendable () -> Void,
        restSeconds: Int = ActivationMonitor.defaultRestSeconds
    ) {
        self.source = source
        self.strokeLeftLock = strokeLeftLock
        self.restSeconds = restSeconds
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // Not `source.stop()`: a source this monitor owns stops itself, and reaching out here recurses.
        rebuild.withLock { $0?.cancel() }
        continuation.finish()
    }

    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        stop()
        guard binding.isDeliverable else {
            throw .shortcutUnavailable
        }
        activeBinding.withLock { $0 = binding }
        recogniser.withLock { $0 = HotkeyRecogniser(binding: binding) }
        let continuation = continuation
        source.onGaveUp { [weak self] in self?.sourceGaveUp() }
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
        rebuild.withLock { $0?.cancel() }
        source.stop()
        // A hold interrupted by stopping is a release, or the microphone stays open.
        recogniser.withLock { current in
            if let owed = current?.finish() { continuation.yield(owed) }
            current = nil
        }
    }

    /// The source left its tap off; release any hold it can no longer report on, then rest and rebuild it.
    private func sourceGaveUp() {
        Self.log.error("the shortcut's tap gave up; rebuilding after \(self.restSeconds, privacy: .public)s")
        // Not `source.stop()`: the tap is already off, and tearing it down runs on the callback's own thread.
        recogniser.withLock { current in
            if let owed = current?.finish() { continuation.yield(owed) }
            current = nil
        }
        rebuild.withLock {
            $0 = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.restSeconds))
                // `Task.sleep` swallows cancellation into a thrown error `try?` discards, so it is checked here.
                guard !Task.isCancelled, let binding = activeBinding.withLock({ $0 }) else { return }
                do {
                    try start(binding: binding)
                    Self.log.error(
                        "the shortcut's tap is back after resting \(self.restSeconds, privacy: .public)s")
                } catch {
                    Self.log.error(
                        "the shortcut's tap could not rebuild: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        }
    }
}
