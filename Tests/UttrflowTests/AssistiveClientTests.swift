// Tests that asking this process for its accessibility tree reads its interface on the main thread.

import AppKit
import ApplicationServices
import Synchronization
import Testing

@MainActor
@Suite(
    "Asking this process for its accessibility tree",
    .enabled(if: AXIsProcessTrusted(), "AppKit answers an in-process query only for a trusted client")
)
struct AssistiveClientTests {
    /// A window that notes, for each time one test asks for its accessibility parent, whether that was on the main thread.
    private final class ThreadNotingWindow: NSWindow {
        let askedOnMainThread = Mutex<[Bool]>([])
        /// The test whose asks are noted, since every other test's ask walks this window too.
        let asker = Mutex<Test.ID?>(nil)

        nonisolated override func accessibilityParent() -> Any? {
            guard let current = Test.current?.id, current == asker.withLock({ $0 }) else { return nil }
            askedOnMainThread.withLock { $0.append(Thread.isMainThread) }
            return nil
        }
    }

    @Test("AppKit reads a window on the main thread, where windows and menu-bar items change")
    func readsTheInterfaceOnTheMainThread() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = ThreadNotingWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 200, height: 200),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let asker = try #require(Test.current).id
        window.asker.withLock { $0 = asker }
        defer { window.close() }
        window.orderFrontRegardless()

        await askAsAnAssistiveApp()

        #expect(window.askedOnMainThread.withLock { $0 } == [true])
    }
}
