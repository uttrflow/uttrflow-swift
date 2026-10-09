// Asks this process for its accessibility tree the way VoiceOver does, which is what makes SwiftUI build it.

import ApplicationServices
import Foundation

/// Asks on the main thread: AppKit answers an in-process query on the calling thread and reads main-actor state.
@MainActor
func askAsAnAssistiveApp() async {
    var value: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(
        AXUIElementCreateApplication(getpid()), kAXChildrenAttribute as CFString, &value)
    // Suspends rather than running the loop nested, so no other test's work runs inside the caller's.
    try? await Task.sleep(for: .milliseconds(200))
}
