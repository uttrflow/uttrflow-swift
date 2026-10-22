// Watches whether the main actor keeps turning, so a test can fail on a stall no stage budget sees.
import Foundation
private import Synchronization

/// Beats on the main queue every millisecond and keeps the longest gap between two beats, less the time the main thread sat ready but unscheduled.
@MainActor
public final class MainActorHeartbeat {
    private var lastBeat: ContinuousClock.Instant?
    private var starvedAtLastBeat = Duration.zero
    private var timer: (any DispatchSourceTimer)?
    private var watch: StarvationWatch?

    /// The longest time the main actor went without letting a beat run, since ``start()``, not counting time the host gave its thread no processor.
    public private(set) var longestGap: Duration = .zero

    public init() {}

    /// Starts beating; the first gap is measured from now.
    public func start() {
        let watch = StarvationWatch(watching: pthread_mach_thread_np(pthread_self()))
        self.watch = watch
        lastBeat = .now
        starvedAtLastBeat = watch.starved
        // A main-queue timer, not a sleeping task, so a beat never waits on the cooperative pool's threads.
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(1), repeating: .milliseconds(1), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.beat() } }
        timer.resume()
        self.timer = timer
    }

    /// Stops beating and returns the longest gap, counting the one that ends now.
    public func stop() -> Duration {
        timer?.cancel()
        timer = nil
        beat()
        watch?.stop()
        watch = nil
        return longestGap
    }

    /// The longest gap while the main actor does nothing for `span`, which is what the host's load alone costs.
    public static func idleGap(over span: Duration = .milliseconds(200)) async -> Duration {
        let heartbeat = MainActorHeartbeat()
        heartbeat.start()
        try? await Task.sleep(for: span)
        return heartbeat.stop()
    }

    private func beat() {
        let now = ContinuousClock.now
        let starved = watch?.starved ?? starvedAtLastBeat
        if let lastBeat {
            longestGap = max(longestGap, lastBeat.duration(to: now) - (starved - starvedAtLastBeat))
        }
        lastBeat = now
        starvedAtLastBeat = starved
    }
}

/// Samples one thread from a high-priority thread of its own and adds up the time it is ready to run but given no processor.
private final class StarvationWatch: Sendable {
    /// How long a ready thread's processor time may stand still before it counts as starved; the kernel updates a running thread's time about every 10 ms.
    static let tick = Duration.milliseconds(20)
    static let interval: useconds_t = 250

    private struct State {
        var starved = Duration.zero
        var stopped = false
    }

    private let state = Mutex(State())

    init(watching thread: thread_act_t) {
        let sampler = Thread { [self] in sample(thread) }
        sampler.qualityOfService = .userInteractive
        sampler.start()
    }

    /// The time the watched thread has spent ready but unscheduled since the watch began.
    var starved: Duration { state.withLock(\.starved) }

    func stop() { state.withLock { $0.stopped = true } }

    private func sample(_ thread: thread_act_t) {
        var streak: (since: ContinuousClock.Instant, time: Duration, counted: Duration)?
        while !state.withLock(\.stopped) {
            let now = ContinuousClock.now
            if let reading = Self.reading(of: thread), reading.ready {
                if let open = streak, open.time == reading.time {
                    let excess = max(.zero, open.since.duration(to: now) - Self.tick)
                    state.withLock { $0.starved += excess - open.counted }
                    streak = (open.since, open.time, excess)
                } else {
                    streak = (now, reading.time, .zero)
                }
            } else {
                streak = nil
            }
            usleep(Self.interval)
        }
    }

    /// The thread's processor time so far and whether it is ready to run, or `nil` if the kernel will not say.
    private static func reading(of thread: thread_act_t) -> (time: Duration, ready: Bool)? {
        var info = thread_basic_info()
        let words = MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(words)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let seconds = Int64(info.user_time.seconds) + Int64(info.system_time.seconds)
        let microseconds = Int64(info.user_time.microseconds) + Int64(info.system_time.microseconds)
        return (.seconds(seconds) + .microseconds(microseconds), info.run_state == TH_STATE_RUNNING)
    }
}
