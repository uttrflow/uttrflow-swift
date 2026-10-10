// Fills the shared dispatch pool, so a test can show that blocking work still gets a thread when every shared one is taken.

import Foundation
import Synchronization

/// Holds every thread the shared dispatch pool may run at once, each blocked, until released.
public final class BusyDispatchPool: Sendable {
    /// The pool's limit on threads running shared-queue work; the kernel's default when it cannot be read.
    public static var limit: Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.wq_max_constrained_threads", &value, &size, nil, 0) == 0, value > 0 else {
            return 64
        }
        return Int(value)
    }

    private let gate = DispatchSemaphore(value: 0)
    /// How many held items have started, and whether the pool is full or the hold has ended.
    private let state = Mutex(State())

    private struct State {
        var started = 0
        var waiting: CheckedContinuation<Void, Never>?
        var ended = false
        var endedByRelease = false
    }

    /// Starts `limit` blocked items on the shared pool and returns once every one of them holds a thread.
    ///
    /// The hold lasts until ``release()``, or until `backstop` passes, so a run that waits for the pool fails
    /// its test rather than hanging the whole process.
    public static func fill(backstop: Duration = .seconds(20)) async -> BusyDispatchPool {
        let pool = BusyDispatchPool()
        let count = limit
        // A thread of its own, since every shared one is about to be held.
        Thread {
            Thread.sleep(forTimeInterval: Double(backstop.components.seconds))
            pool.end(byRelease: false)
        }.start()
        await withCheckedContinuation { (full: CheckedContinuation<Void, Never>) in
            pool.state.withLock { $0.waiting = full }
            for _ in 0..<count {
                DispatchQueue.global(qos: .utility).async {
                    pool.started(of: count)
                    pool.gate.wait()
                    pool.gate.signal()
                }
            }
        }
        return pool
    }

    /// Whether the hold lasted until ``release()``, rather than being ended by the backstop.
    public var heldUntilReleased: Bool { state.withLock { $0.endedByRelease } }

    /// Frees every held thread.
    public func release() { end(byRelease: true) }

    private func started(of count: Int) {
        let full = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.started += 1
            guard state.started == count else { return nil }
            defer { state.waiting = nil }
            return state.waiting
        }
        full?.resume()
    }

    private func end(byRelease: Bool) {
        let (first, waiting) = state.withLock { state -> (Bool, CheckedContinuation<Void, Never>?) in
            guard !state.ended else { return (false, nil) }
            state.ended = true
            state.endedByRelease = byRelease
            defer { state.waiting = nil }
            return (true, state.waiting)
        }
        guard first else { return }
        waiting?.resume()
        gate.signal()
    }
}
