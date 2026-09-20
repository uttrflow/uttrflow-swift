// Tests that a key tap gives back the port and the state it held, however it ends.
import CoreFoundation
import Dispatch
import Testing

@testable import UttrflowInput

/// Lets the tap's own thread reach the tap it is running, which only exists once `create` returns.
private final class TapBox: @unchecked Sendable {
    var tap: InterceptorTap?
    var alive: CFRunLoopSource?
}

@Suite("The key interceptor's tap lifetime", .timeLimit(.minutes(1)))
struct KeyInterceptorLifetimeTests {
    /// A plain Mach port, which stands in for an event tap without needing Accessibility.
    private static func makePort() -> CFMachPort? {
        CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
    }

    /// A state with a resumed source of its own, since libdispatch traps on freeing a suspended one.
    private static func makeState() -> TapState {
        let source = DispatchSource.makeUserDataAddSource(queue: DispatchQueue(label: "test.tap-state"))
        source.resume()
        return TapState(signal: source)
    }

    /// The retain count the port should end at once invalidated, measured on a control port invalidated alone.
    private static func settledCount(of port: CFMachPort) throws -> CFIndex {
        let control = try #require(makePort())
        let before = CFGetRetainCount(control)
        CFMachPortInvalidate(control)
        return CFGetRetainCount(port) - (before - CFGetRetainCount(control))
    }

    /// A signal the tap fires once it has released its state, buffered so it may fire before anyone waits.
    private struct Release {
        let stream: AsyncStream<Void>
        let fire: @Sendable () -> Void

        init() {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            self.stream = stream
            fire = {
                continuation.yield()
                continuation.finish()
            }
        }

        func wait() async {
            for await _ in stream { return }
        }
    }

    /// Starts and stops one tap on the port, returning once the tap has released its state and been freed.
    private static func cycle(state: TapState, port: CFMachPort) async throws {
        let release = Release()
        do {
            let tap = try InterceptorTap.create(state: state, makePort: { _ in port }, released: release.fire)
            tap.run()
            tap.stop()
        }
        await release.wait()
    }

    @Test("a start, stop and start leaves the first port's retain count where it began")
    func restartingReleasesThePreviousPort() async throws {
        let state = Self.makeState()
        let first = try #require(Self.makePort())
        let second = try #require(Self.makePort())
        let settled = try Self.settledCount(of: first)

        try await Self.cycle(state: state, port: first)
        try await Self.cycle(state: state, port: second)

        #expect(CFGetRetainCount(first) == settled, "retain count \(CFGetRetainCount(first)) vs \(settled)")
    }

    @Test("adopting a new port releases the one it replaces")
    func adoptingReleasesTheReplacedPort() throws {
        let state = Self.makeState()
        let first = try #require(Self.makePort())
        let second = try #require(Self.makePort())
        let baseline = CFGetRetainCount(first)

        state.adopt(first)
        state.adopt(second)

        #expect(CFGetRetainCount(first) == baseline, "retain count \(CFGetRetainCount(first)) vs \(baseline)")
    }

    @Test("a stopped tap releases the port it gave the state")
    func stoppingReleasesThePort() async throws {
        let state = Self.makeState()
        let port = try #require(Self.makePort())
        let settled = try Self.settledCount(of: port)

        try await Self.cycle(state: state, port: port)

        #expect(CFGetRetainCount(port) == settled, "retain count \(CFGetRetainCount(port)) vs \(settled)")
    }

    @Test("a running tap keeps its state alive, and a stopped one lets it go")
    func runningTapHoldsTheState() async throws {
        let port = try #require(Self.makePort())
        let release = Release()
        weak var weakState: TapState?
        var tap: InterceptorTap?
        do {
            let state = Self.makeState()
            weakState = state
            tap = try InterceptorTap.create(state: state, makePort: { _ in port }, released: release.fire)
        }
        tap?.run()
        #expect(weakState != nil, "the state was freed while its tap was running")
        tap?.stop()
        await release.wait()
        #expect(weakState == nil, "the state outlived its stopped tap")
        withExtendedLifetime(tap) {}
    }

    @Test("a stop that lands after the source is added but before the run loop runs still ends the thread")
    func stoppingBeforeTheLoopRunsEndsTheThread() async throws {
        let port = try #require(Self.makePort())
        let keepAlive = try #require(Self.makePort())
        let release = Release()
        let box = TapBox()
        box.alive = try #require(CFMachPortCreateRunLoopSource(nil, keepAlive, 0))
        let tap = try InterceptorTap.create(
            state: Self.makeState(), makePort: { _ in port }, released: release.fire,
            beforeLoop: {
                // A second live source means the loop would run on even though the tap's own source is gone.
                CFRunLoopAddSource(CFRunLoopGetCurrent(), box.alive, .commonModes)
                box.tap?.stop()
            })
        box.tap = tap
        tap.run()
        await release.wait()
        box.tap = nil
        CFMachPortInvalidate(keepAlive)
    }

    @Test("a tap stopped before it runs still releases its state")
    func stoppingBeforeRunningReleasesTheState() throws {
        let port = try #require(Self.makePort())
        weak var weakState: TapState?
        let tap: InterceptorTap
        do {
            let state = Self.makeState()
            weakState = state
            tap = try InterceptorTap.create(state: state) { _ in port }
        }
        tap.stop()
        tap.run()
        #expect(weakState == nil, "the state outlived a tap stopped before it ran")
        withExtendedLifetime(tap) {}
    }

    @Test("a tap that is never run or stopped releases its state and port when it is freed")
    func discardedTapReleasesEverything() throws {
        let port = try #require(Self.makePort())
        let settled = try Self.settledCount(of: port)
        weak var weakState: TapState?
        do {
            let state = Self.makeState()
            weakState = state
            _ = try InterceptorTap.create(state: state) { _ in port }
        }
        #expect(weakState == nil, "the state outlived a discarded tap")
        #expect(CFGetRetainCount(port) == settled, "retain count \(CFGetRetainCount(port)) vs \(settled)")
    }

    @Test("a refused tap throws and releases the state it was offered")
    func refusedTapReleasesTheState() {
        weak var weakState: TapState?
        do {
            let state = Self.makeState()
            weakState = state
            #expect(throws: KeyInterceptorFailure.tapRefused) {
                try InterceptorTap.create(state: state) { _ in nil }
            }
        }
        #expect(weakState == nil, "the state outlived a refused tap")
    }
}
