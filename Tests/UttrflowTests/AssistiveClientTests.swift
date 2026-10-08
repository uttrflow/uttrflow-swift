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
    /// A window that notes, for each time it is asked for its accessibility parent, whether that was on the main thread.
    private final class ThreadNotingWindow: NSWindow {
        let askedOnMainThread = Mutex<[Bool]>([])

        nonisolated override func accessibilityParent() -> Any? {
            askedOnMainThread.withLock { $0.append(Thread.isMainThread) }
            return nil
        }
    }

    @Test("AppKit reads a window on the main thread, where windows and menu-bar items change")
    func readsTheInterfaceOnTheMainThread() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = ThreadNotingWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 200, height: 200),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.orderFrontRegardless()

        askAsAnAssistiveApp()

        #expect(window.askedOnMainThread.withLock { $0 } == [true])
    }
}
