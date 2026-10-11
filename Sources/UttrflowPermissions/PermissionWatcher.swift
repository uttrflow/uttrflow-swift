public import UttrflowCore

/// Reads one permission on a cheap timer and reports each change once, so a revoked permission is a state, not a failure.
@MainActor
public final class PermissionWatcher {
    private let gate: any PermissionGate
    private let interval: Duration
    private let onChange: @MainActor (PermissionStatus) -> Void
    private var task: Task<Void, Never>?

    /// How often a permission is read when the caller names no interval: once a second, so a change shows within one.
    public static let defaultInterval = Duration.seconds(1)

    /// The status last read, or `nil` before the first read.
    public private(set) var status: PermissionStatus?

    /// Watches `gate` every `interval`; `onChange` is told each change after the first reading.
    public init(
        gate: any PermissionGate,
        interval: Duration = PermissionWatcher.defaultInterval,
        onChange: @escaping @MainActor (PermissionStatus) -> Void
    ) {
        self.gate = gate
        self.interval = interval
        self.onChange = onChange
    }

    /// Starts reading; a second call while running does nothing.
    public func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.read()
                do { try await Task.sleep(for: self.interval) } catch { return }
            }
        }
    }

    /// Stops reading.
    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Reads once, telling `onChange` when the status differs from the previous reading.
    func read() async {
        let current = await gate.status()
        let previous = status
        status = current
        guard let previous, previous != current else { return }
        onChange(current)
    }
}
