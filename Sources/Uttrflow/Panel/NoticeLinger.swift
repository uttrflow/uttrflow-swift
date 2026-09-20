// The timer that closes the panel after a notice, unless the person goes on using it.

import Foundation

/// Closes the panel once a notice has been read, and never while the person is still working in it.
@MainActor
final class NoticeLinger {
    /// Long enough to read one short sentence and no more, since the panel is in the way.
    static let standard = Duration.seconds(2.5)

    private let linger: Duration
    private var task: Task<Void, Never>?

    init(linger: Duration = NoticeLinger.standard) {
        self.linger = linger
    }

    /// Whether a close is still waiting to happen.
    var isPending: Bool { task != nil }

    /// Starts the wait again; `close` runs only if nothing interrupts it first.
    func start(close: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [weak self, linger] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled else { return }
            self?.task = nil
            close()
        }
    }

    /// Called on any key or intent, so the panel stays while it is in use.
    func interrupt() {
        task?.cancel()
        task = nil
    }
}
