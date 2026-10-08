// Asks this process for its accessibility tree the way VoiceOver does, which is what makes SwiftUI build it.

import ApplicationServices
import Foundation

/// Asks on the main thread: AppKit answers an in-process query on the calling thread and reads main-actor state.
@MainActor
func askAsAnAssistiveApp() {
    var value: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(
        AXUIElementCreateApplication(getpid()), kAXChildrenAttribute as CFString, &value)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
}
