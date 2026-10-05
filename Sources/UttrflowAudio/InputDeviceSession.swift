// Owns an input device's lifecycle, so a sample pump does not have to.
private import Synchronization
public import UttrflowCore

/// One input device, opened and closed, with no audio machinery visible to whoever retries it.
public protocol InputDevice: Sendable {
    /// Opens the device, throwing what a caller would have thrown.
    func open() throws(AudioCaptureError)

    /// Closes the device. Safe to call when it is not open.
    func close()
}

/// How long to wait before each reopen attempt, so a device that is re-enumerating is given time to appear.
public struct ReopenSchedule: Sendable, Equatable {
    /// Spread across roughly three seconds, which covers a Bluetooth re-enumeration and a sample-rate change.
    public static let standard = ReopenSchedule(delays: [
        .milliseconds(100), .milliseconds(200), .milliseconds(400), .milliseconds(800),
        .milliseconds(1500),
    ])

    public let delays: [Duration]

    public init(delays: [Duration]) {
        self.delays = delays
    }

    /// How long the whole schedule waits, which is what a caller has to be willing to wait for.
    public var total: Duration { delays.reduce(.zero, +) }
}

/// What the device is doing, so a caller can tell a gap from an ending.
public enum DeviceHealth: Sendable, Equatable {
    case live
    case reopening
    case gone
}

/// Reopens a device that macOS pulled out from under a recording, and says so when it cannot.
public final class InputDeviceSession: Sendable {
    private struct State {
        var health: DeviceHealth = .gone
        var reopening: Task<Void, Never>?
        var report: (@Sendable (CaptureInterruption) -> Void)?
        // A change seen while already reopening, so the in-flight open cannot be published as live.
        var pendingChange = false
    }

    /// What a change should do, depending on whether a reopen is already under way.
    private enum ChangeAction {
        case begin(@Sendable (CaptureInterruption) -> Void)
        case coalesced
        case ignored
    }

    private let device: any InputDevice
    private let schedule: ReopenSchedule
    private let pause: @Sendable (Duration) async throws -> Void
    private let state = Mutex(State())

    public init(
        device: any InputDevice, schedule: ReopenSchedule = .standard,
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.device = device
        self.schedule = schedule
        self.pause = pause
    }

    /// What the device is doing right now.
    public var health: DeviceHealth { state.withLock(\.health) }

    /// Opens the device for the first time, where a failure is the caller's to see rather than to retry.
    public func open(
        reporting: @escaping @Sendable (CaptureInterruption) -> Void
    ) throws(AudioCaptureError) {
        state.withLock { $0.report = reporting }
        do {
            try device.open()
        } catch {
            state.withLock { $0.report = nil }
            throw error
        }
        state.withLock {
            $0.health = .live
            $0.pendingChange = false
        }
    }

    /// Closes the device and abandons any reopen in flight.
    public func close() {
        let reopening = state.withLock { state -> Task<Void, Never>? in
            defer { state = State() }
            return state.reopening
        }
        reopening?.cancel()
        device.close()
    }

    /// Reports a hole in a live device's audio, so the recording is refused rather than joined across it.
    public func timelineBroke() {
        let report = state.withLock { $0.health == .live ? $0.report : nil }
        report?(.began)
    }

    /// Reopens after a configuration change, or coalesces it into a retry already under way; nil when coalesced or gone.
    @discardableResult
    public func deviceChanged() -> Task<Void, Never>? {
        let action = state.withLock { state -> ChangeAction in
            switch state.health {
            case .live:
                state.health = .reopening
                state.pendingChange = false
                return .begin(state.report ?? { _ in })
            case .reopening:
                state.pendingChange = true
                return .coalesced
            case .gone:
                return .ignored
            }
        }
        guard case .begin(let begun) = action else { return nil }
        // Said before the retry, because a stop landing mid-reopen would otherwise report nothing at all.
        begun(.began)
        device.close()
        let reopening = Task { [self] in await reopen() }
        // Only if the retry has not already finished, which it can when the schedule waits for nothing.
        state.withLock { if $0.health == .reopening { $0.reopening = reopening } }
        return reopening
    }

    /// Tries the schedule in order, stopping at the first open that succeeds.
    private func reopen() async {
        for delay in schedule.delays {
            // Waiting first: the device that just went is not back yet, and nothing else times this.
            guard (try? await pause(delay)) != nil, !Task.isCancelled else { return }
            guard state.withLock(\.health) == .reopening else { return }
            do {
                try device.open()
                let outcome = state.withLock { state -> Bool? in
                    guard state.health == .reopening else { return nil }
                    // Another change landed before this open could be trusted; it is not live yet.
                    guard !state.pendingChange else {
                        state.pendingChange = false
                        return false
                    }
                    state.health = .live
                    state.reopening = nil
                    return true
                }
                switch outcome {
                case true:
                    return
                case false:
                    // Close what just opened and keep going: the schedule still has budget.
                    device.close()
                    continue
                case nil:
                    // A close that landed while this was opening leaves a device nothing else would shut.
                    device.close()
                    return
                }
            } catch let error {
                if error == .microphoneDenied {
                    endReopen(with: .microphoneDenied)
                    return
                }
                continue
            }
        }
        endReopen(
            with: .engineFailed(description: "The microphone did not come back after the device changed."))
    }

    private func endReopen(with error: AudioCaptureError) {
        let report = state.withLock { state -> (@Sendable (CaptureInterruption) -> Void)? in
            guard state.health == .reopening else { return nil }
            state.health = .gone
            state.reopening = nil
            defer { state.report = nil }
            return state.report
        }
        report?(.ended(error))
    }
}
