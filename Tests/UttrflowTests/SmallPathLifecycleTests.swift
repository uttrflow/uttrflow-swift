import ApplicationServices
import Foundation
import Synchronization
import Testing
import UttrflowAI
import UttrflowContext
import UttrflowDictionary

@testable import Uttrflow

private actor SmallPathGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private final class ImmediateObservationWorker: FocusedFieldAXWorking, Sendable {
    private let state = Mutex((contexts: [FocusedFieldValueObserverCallbackContext](), refreshes: 0))
    var contexts: [FocusedFieldValueObserverCallbackContext] { state.withLock { $0.contexts } }
    var refreshes: Int { state.withLock { $0.refreshes } }

    func observe(
        _ target: FocusedFieldObservationTarget?, callbackContext: FocusedFieldValueObserverCallbackContext,
        isCurrent: @Sendable () -> Bool
    ) {
        if isCurrent() { state.withLock { $0.contexts.append(callbackContext) } }
    }

    func focusedElementChanged(isCurrent: @Sendable () -> Bool) {
        if isCurrent() { state.withLock { $0.refreshes += 1 } }
    }

    func stop() {}
}

@MainActor
@Suite("Focused observer callback lifecycle")
struct FocusedObserverLifecycleTests {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }

    @Test("a focus callback refreshes the worker while unrelated notifications remain silent")
    func focusRefreshAndUnknownNotification() async throws {
        let worker = ImmediateObservationWorker()
        let observer = FocusedFieldValueObserver(worker: worker)
        defer { observer.stop() }
        var values = 0
        var menus: [Bool] = []
        observer.start(
            for: nil, onValueChanged: { values += 1 }, onNativeMenuVisibilityChanged: { menus.append($0) })
        #expect(await eventually { worker.contexts.count == 1 })
        let context = try #require(worker.contexts.first)
        context.received(kAXFocusedUIElementChangedNotification as String)
        #expect(await eventually { worker.refreshes == 1 })
        context.received("SyntheticUnknownNotification")
        #expect(values == 0)
        #expect(menus.isEmpty)
        context.received(kAXValueChangedNotification as String)
        #expect(values == 1)
    }

    @Test("changing targets and resetting a current callback close the previous menu exactly once")
    func resetAndTargetChangeCloseMenus() async throws {
        let worker = ImmediateObservationWorker()
        let observer = FocusedFieldValueObserver(worker: worker)
        defer { observer.stop() }
        var menus: [Bool] = []
        observer.start(for: nil, onValueChanged: {}, onNativeMenuVisibilityChanged: { menus.append($0) })
        #expect(await eventually { worker.contexts.count == 1 })
        let first = try #require(worker.contexts.first)
        first.received(kAXMenuOpenedNotification as String)
        observer.refresh(
            for: FocusedFieldObservationTarget(
                processIdentifier: 7, bundleIdentifier: "com.example.synthetic"))
        #expect(await eventually { worker.contexts.count == 2 })
        #expect(menus == [true, false])
        let current = worker.contexts[1]
        current.received(kAXMenuOpenedNotification as String)
        current.reset()
        current.reset()
        #expect(menus == [true, false, true, false])
    }

    @Test("an unused native observer can stop repeatedly and release without contacting an application")
    func nativeObserverReleasesWithoutStarting() {
        weak var released: FocusedFieldValueObserver?
        do {
            let observer = FocusedFieldValueObserver()
            released = observer
            observer.refresh(for: nil)
            observer.stop()
            observer.stop()
        }
        #expect(released == nil)
    }
}

@Suite("Cancelled small path requests")
struct CancelledSmallPathTests {
    private actor FieldReads {
        private(set) var calls = 0
        func read() -> LandedFieldRead? {
            calls += 1
            return calls == 1
                ? LandedFieldRead(
                    field: FocusedFieldIdentity(processIdentifier: 7, elementHash: 11), text: "synthetic")
                : nil
        }
    }

    @Test("an already cancelled surroundings caller cannot seed the next caller's cache")
    func cancelledBeforeCacheRequest() async {
        let cache = SuggestionContextCache()
        let gate = SmallPathGate()
        let read = Task {
            await gate.wait()
            return await cache.surroundings(for: "synthetic") {
                Surroundings(windowTitle: "Cancelled fixture", text: "synthetic")
            }
        }
        read.cancel()
        await gate.open()
        #expect(await read.value == nil)
        let next = await cache.surroundings(for: "synthetic") {
            Surroundings(windowTitle: "Fresh fixture", text: "synthetic")
        }
        #expect(next?.windowTitle == "Fresh fixture")
    }

    @Test("cancellation ends the edit-away delay and an unreadable second field vetoes nothing")
    func cancellationEndsDefaultDelay() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "uttrflow-edit-away-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        let reader = FieldReads()
        let watch = EditAwayWatch(dictionary: dictionary, readField: { await reader.read() })
        let gate = SmallPathGate()
        let task = Task {
            await gate.wait()
            await watch.watch([EditAway.Applied(entryID: UUID(), word: "synthetic")], inserted: "synthetic")
        }
        task.cancel()
        await gate.open()
        await task.value
        #expect(await reader.calls == 2)
        #expect(await dictionary.refusedWords().isEmpty)
    }
}
