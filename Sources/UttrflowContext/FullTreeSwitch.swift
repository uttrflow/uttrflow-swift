import Foundation
import UttrflowCore

private import Synchronization

/// Switches on a browser engine's full Accessibility tree in the applications that need it, and off again. See `Docs/predict-reliability.md`.
public final class FullTreeSwitch: Sendable {
    /// One application's switches as Accessibility exposes them: a read that is `nil` where unsupported, and a write that says whether it took.
    struct Host {
        let read: (_ attribute: String) -> Bool?
        let write: (_ attribute: String, _ isOn: Bool) -> Bool
    }

    /// The switch an application built on a bundled browser engine offers, which changes nothing but the tree.
    static let manualAttribute = "AXManualAccessibility"

    /// The switch a screen reader sets, which a Chromium browser honours where it ignores the manual one.
    static let enhancedAttribute = "AXEnhancedUserInterface"

    /// The Chromium browsers, the only applications the screen reader's switch is set on, since it slows window animations elsewhere.
    static let chromiumBrowsers = DestinationRules.chromiumBrowsers

    private static let normalizedChromiumBrowsers = Set(chromiumBrowsers.map { $0.lowercased() })

    /// How long after an attempt that got no answer the same process may be asked again.
    static let retryInNanoseconds: UInt64 = 5_000_000_000

    /// How many attempts one process is given while the loop runs, so an application that never answers is not asked forever.
    static let mostAttempts = 4

    private struct State {
        /// Invalidates field reads that began before the last stop.
        var generation: UInt64 = 0
        /// How many attempts each process has had and when the last began, in uptime nanoseconds.
        var attempts: [Int32: (count: Int, at: UInt64)] = [:]
        /// The processes whose switch is settled, on by this switch or by something else, which are never asked again.
        var settled: Set<Int32> = []
        /// The processes this switch saw turn on after its own write, with the attribute that did.
        var switched: [Int32: String] = [:]
        /// Every attribute this switch wrote on, answered or not, which is what stopping turns off.
        var written: [Int32: Set<String>] = [:]
    }

    private struct SwitchRequest {
        let processIdentifier: Int32
        let generation: UInt64
        let host: Host
    }

    private let state = Mutex(State())
    private let operations = Mutex(())

    public init() {}

    /// Whether a read calls for the tree: always in a Chromium browser, whose first read may run out of time, and elsewhere for a text field with no caret.
    static func isNeeded(in bundleIdentifier: String, after reading: FocusedFieldSnapshot?) -> Bool {
        if isChromiumBrowser(bundleIdentifier) { return true }
        guard let reading else { return false }
        return reading.caret == nil && !reading.isSecure && FocusedFieldSnapshot.isTextEntry(reading.role)
    }

    /// The processes whose tree this switch turned on and has not turned off.
    var switchedOn: [Int32: String] { state.withLock { $0.switched } }

    /// The current run, captured before a field read starts and invalidated when the loop stops.
    var generation: UInt64 { state.withLock { $0.generation } }

    /// Begins a new session without waiting on older Accessibility work, so a queued stop cannot reach it.
    @discardableResult
    func beginSession() -> UInt64 {
        state.withLock { state in
            state.generation &+= 1
            state.attempts = [:]
            state.settled = []
            return state.generation
        }
    }

    /// Invalidates field reads without waiting for an in-flight Accessibility operation.
    @discardableResult
    func invalidatePendingReads() -> UInt64 {
        state.withLock { state in
            state.generation += 1
            return state.generation
        }
    }

    /// Whether this process may be asked now: not settled, attempts left, and the last one long enough ago; asking counts as an attempt.
    private func mayAsk(_ processIdentifier: Int32, generation: UInt64, at now: UInt64) -> Bool {
        state.withLock { state in
            guard state.generation == generation,
                !state.settled.contains(processIdentifier)
            else { return false }
            let last = state.attempts[processIdentifier]
            if let last {
                guard last.count < Self.mostAttempts, now >= last.at + Self.retryInNanoseconds else {
                    return false
                }
            }
            state.attempts[processIdentifier] = ((last?.count ?? 0) + 1, now)
            return true
        }
    }

    /// Turns the full tree on in one application; an attempt with no answer is tried again later, a few times at most.
    func switchOn(
        processIdentifier: Int32, bundleIdentifier: String, host: Host,
        generation requestedGeneration: UInt64? = nil,
        at now: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        operations.withLock { _ in
            let generation = requestedGeneration ?? self.generation
            guard mayAsk(processIdentifier, generation: generation, at: now) else { return }
            let request = SwitchRequest(
                processIdentifier: processIdentifier, generation: generation, host: host)
            // A Chromium browser decides on the screen reader's switch, so the manual one alone never settles it.
            let attributes =
                Self.isChromiumBrowser(bundleIdentifier)
                ? [Self.manualAttribute, Self.enhancedAttribute] : [Self.manualAttribute]
            for (index, attribute) in attributes.enumerated() {
                let wrote = state.withLock { $0.written[processIdentifier]?.contains(attribute) ?? false }
                if attemptAttribute(
                    attribute, decides: index == attributes.count - 1, wasWritten: wrote,
                    request: request)
                {
                    return
                }
            }
        }
    }

    private func attemptAttribute(
        _ attribute: String, decides: Bool, wasWritten: Bool, request: SwitchRequest
    ) -> Bool {
        guard isCurrent(request.generation) else { return false }
        let wasOn = request.host.read(attribute)
        guard isCurrent(request.generation) else { return false }
        if wasOn == true {
            guard decides else { return false }
            return settle(attribute, wasWritten: wasWritten, request: request)
        }
        let recorded = state.withLock { state -> Bool in
            guard state.generation == request.generation else { return false }
            // The write is recorded before its answer, since one that times out may still take.
            _ = state.written[request.processIdentifier, default: []].insert(attribute)
            return true
        }
        guard recorded, isCurrent(request.generation) else { return false }
        // Chrome answers a write it has applied as not implemented, so the value read back decides.
        let writeSucceeded = request.host.write(attribute, true)
        guard isCurrent(request.generation) else { return false }
        let isOn: Bool
        if writeSucceeded {
            isOn = true
        } else {
            guard isCurrent(request.generation) else { return false }
            isOn = request.host.read(attribute) == true
            guard isCurrent(request.generation) else { return false }
        }
        guard isOn, decides else { return false }
        return settle(attribute, wasWritten: true, request: request)
    }

    private func settle(_ attribute: String, wasWritten: Bool, request: SwitchRequest) -> Bool {
        state.withLock { state in
            guard state.generation == request.generation else { return false }
            state.settled.insert(request.processIdentifier)
            if wasWritten { state.switched[request.processIdentifier] = attribute }
            return true
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        state.withLock { $0.generation == generation }
    }

    private static func isChromiumBrowser(_ bundleIdentifier: String) -> Bool {
        normalizedChromiumBrowsers.contains(bundleIdentifier.lowercased())
    }

    /// Turns off trees for departed processes, optionally retaining the active process, and invalidates earlier field reads.
    func switchOffEverything(except retainedProcessIdentifier: Int32? = nil, host: (Int32) -> Host) {
        performSwitchOffEverything(except: retainedProcessIdentifier, generation: nil, host: host)
    }

    /// Finishes one queued release only if no newer activation or stop has superseded it.
    func switchOffEverything(
        except retainedProcessIdentifier: Int32? = nil, generation expectedGeneration: UInt64,
        host: (Int32) -> Host
    ) {
        performSwitchOffEverything(
            except: retainedProcessIdentifier, generation: expectedGeneration, host: host)
    }

    private func performSwitchOffEverything(
        except retainedProcessIdentifier: Int32?, generation expectedGeneration: UInt64?,
        host: (Int32) -> Host
    ) {
        operations.withLock { _ in
            let written = state.withLock { state -> [Int32: Set<String>]? in
                if let expectedGeneration, state.generation != expectedGeneration { return nil }
                if expectedGeneration == nil { state.generation += 1 }
                let written = state.written.filter { $0.key != retainedProcessIdentifier }
                let retained =
                    retainedProcessIdentifier.flatMap { processIdentifier in
                        state.written[processIdentifier].map { [processIdentifier: $0] }
                    } ?? [:]
                state = State(
                    generation: state.generation,
                    attempts: state.attempts.filter { $0.key == retainedProcessIdentifier },
                    settled: retainedProcessIdentifier.map { state.settled.contains($0) ? [$0] : [] } ?? [],
                    switched: state.switched.filter { $0.key == retainedProcessIdentifier },
                    written: retained)
                return written
            }
            guard let written else { return }
            for (processIdentifier, attributes) in written {
                let application = host(processIdentifier)
                for attribute in attributes.sorted() where application.read(attribute) != false {
                    _ = application.write(attribute, false)
                }
            }
        }
    }
}
