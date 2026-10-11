import ApplicationServices
import Synchronization
import Testing

@testable import Uttrflow

private final class ScriptedAXClient: FocusedFieldAXClient {
    var canCreate = true
    var focused: Int? = 11
    var rejected: String?
    var events: [String] = []
    var onCall: () -> Void = {}

    func observer(for process: pid_t) -> Int? {
        events.append("observer:\(process)"); onCall(); return canCreate ? 1 : nil
    }
    func application(for process: pid_t) -> Int { events.append("application"); onCall(); return 10 }
    func setTimeout(_ element: Int) -> AXError {
        events.append("timeout:\(element)"); onCall(); return .success
    }
    func addSource(_ observer: Int) { events.append("addSource"); onCall() }
    func removeSource(_ observer: Int) { events.append("removeSource") }
    func addNotification(
        _ observer: Int, _ element: Int, _ name: CFString, _ context: UnsafeMutableRawPointer
    ) -> AXError {
        let name = name as String
        events.append("add:\(element):\(name)"); onCall()
        return rejected == name ? .notificationUnsupported : .success
    }
    func removeNotification(_ observer: Int, _ element: Int, _ name: CFString) -> AXError {
        events.append("remove:\(element):\(name)"); onCall(); return .success
    }
    func focusedElement(of application: Int) -> Int? { events.append("read"); onCall(); return focused }
    func equal(_ first: Int, _ second: Int) -> Bool { first == second }
}

@MainActor
@Suite("AX observer ownership with private handles")
struct FocusedFieldAXWorkerTests {
    private let target = FocusedFieldObservationTarget(
        processIdentifier: -1, bundleIdentifier: "com.example.editor")

    private func context(
        reset: @escaping @MainActor () -> Void = {}
    ) -> FocusedFieldValueObserverCallbackContext {
        FocusedFieldValueObserverCallbackContext(
            onFocusedElementChanged: {}, onNotification: { _ in }, onObserverReset: reset, isCurrent: { true }
        )
    }

    @Test("focus changes replace only the value observer and stop removes every registration")
    func lifecycle() async {
        let client = ScriptedAXClient()
        let worker = FocusedFieldAXWorker(client: client)
        var resets = 0
        let callback = context { resets += 1 }
        worker.observe(target, callbackContext: callback, isCurrent: { true })
        #expect(client.events.contains("add:11:AXValueChanged"))
        let installs = client.events.filter { $0 == "addSource" }.count
        worker.observe(target, callbackContext: callback, isCurrent: { true })
        #expect(client.events.filter { $0 == "addSource" }.count == installs)
        #expect(client.events.filter { $0 == "add:11:AXValueChanged" }.count == 1)
        client.focused = 12
        worker.focusedElementChanged(isCurrent: { true })
        #expect(client.events.contains("remove:11:AXValueChanged"))
        #expect(client.events.contains("add:12:AXValueChanged"))
        client.focused = nil
        worker.focusedElementChanged(isCurrent: { true })
        #expect(client.events.contains("remove:12:AXValueChanged"))
        worker.stop()
        #expect(client.events.contains("remove:10:AXFocusedUIElementChanged"))
        #expect(client.events.contains("remove:10:AXMenuOpened"))
        #expect(client.events.contains("remove:10:AXMenuClosed"))
        #expect(client.events.filter { $0 == "removeSource" }.count == 1)
        await Task.yield()
        #expect(resets == 1)
        worker.stop()
        worker.observe(nil, callbackContext: callback, isCurrent: { true })
        #expect(client.events.filter { $0 == "removeSource" }.count == 1)
    }

    @Test("a new callback replaces the observer and balances both sources")
    func replacesCallback() {
        let client = ScriptedAXClient()
        let worker = FocusedFieldAXWorker(client: client)
        worker.observe(target, callbackContext: context(), isCurrent: { true })
        worker.observe(target, callbackContext: context(), isCurrent: { true })
        worker.stop()
        #expect(client.events.filter { $0 == "addSource" }.count == 2)
        #expect(client.events.filter { $0 == "removeSource" }.count == 2)
    }

    @Test(
        "unsupported menu notifications leave no half-installed observer",
        arguments: ["AXMenuOpened", "AXMenuClosed"])
    func rejectedMenu(name: String) {
        let client = ScriptedAXClient()
        client.rejected = name
        let worker = FocusedFieldAXWorker(client: client)
        worker.observe(target, callbackContext: context(), isCurrent: { true })
        #expect(!client.events.contains("read"))
        #expect(client.events.contains("removeSource"))
        if name == "AXMenuClosed" { #expect(client.events.contains("remove:10:AXMenuOpened")) }
    }

    @Test("failed creation and a stale request never register callbacks")
    func unavailable() {
        let client = ScriptedAXClient()
        client.canCreate = false
        let worker = FocusedFieldAXWorker(client: client)
        worker.observe(target, callbackContext: context(), isCurrent: { true })
        worker.focusedElementChanged(isCurrent: { true })
        #expect(client.events == ["observer:-1"])
        client.events = []
        worker.observe(target, callbackContext: context(), isCurrent: { false })
        #expect(client.events.isEmpty)
    }

    @Test("cancellation at each platform boundary prevents a later read or registration", arguments: 1...11)
    func cancelled(call: Int) {
        let client = ScriptedAXClient()
        let current = Mutex(true)
        let calls = Mutex(0)
        client.onCall = {
            if calls.withLock({
                $0 += 1; return $0
            }) == call {
                current.withLock { $0 = false }
            }
        }
        let worker = FocusedFieldAXWorker(client: client)
        worker.observe(target, callbackContext: context(), isCurrent: { current.withLock { $0 } })
        let before = client.events.count
        worker.focusedElementChanged(isCurrent: { false })
        worker.stop()
        #expect(!client.events.dropFirst(before).contains(where: { $0.hasPrefix("add:") || $0 == "read" }))
        #expect(client.events.filter { $0 == "removeSource" }.count <= 1)
    }

    @Test("the native adapter refuses a synthetic process without reading a user's field")
    func syntheticNativeHandle() {
        let client = SystemFocusedFieldAXClient()
        let application = client.application(for: -1)
        #expect(client.equal(application, application))
        #expect(client.focusedElement(of: application) == nil)
        _ = client.setTimeout(application)
        if let observer = client.observer(for: -1) {
            client.addSource(observer)
            client.removeSource(observer)
        }
    }
}
