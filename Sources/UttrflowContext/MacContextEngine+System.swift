import AppKit
import ApplicationServices
import Foundation

/// Wires the engine to macOS.
///
/// Excluded from the coverage gate: every line reaches into another running application
/// or asks the window server about one, and what it must never do — wait — is decided in
/// ``MacContextEngine`` and tested there. Kept short enough that reading it is a
/// sufficient review.
extension MacContextEngine {
    /// The engine as the app uses it.
    public convenience init() {
        self.init(
            readFrontmostApplication: { await MainActor.run { MacContextEngine.frontmostApplication() } },
            readFocusedWindow: { await MacContextEngine.focusedWindow(of: $0) },
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
    }

    /// Identity, from NSWorkspace, on the main thread the one place it is safe to read.
    @MainActor
    static func frontmostApplication() -> FrontmostApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostApplication(
            name: app.localizedName,
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier
        )
    }

    /// Title and selection, from Accessibility. `nil` without the permission, where
    /// every call below would return `kAXErrorAPIDisabled` anyway.
    ///
    /// Runs on a thread of its own rather than the cooperative pool. These calls are
    /// synchronous and block until the other app answers, which a napped app measurably
    /// does not do for a tenth of a second; blocking a pool thread for that would stall
    /// unrelated work in the app.
    static func focusedWindow(of application: FrontmostApplication) async -> FocusedWindow? {
        guard AXIsProcessTrusted() else { return nil }
        return await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: read(application.processIdentifier))
            }
        }
    }

    private static let readQueue = DispatchQueue(label: "com.uttrflow.context", qos: .userInitiated)

    private static func read(_ pid: pid_t) -> FocusedWindow {
        let app = AXUIElementCreateApplication(pid)
        // Caps each message so an app that never answers eventually releases this
        // thread. The engine's budget is what the dictation waits for; this is what
        // stops the abandoned read outliving it.
        _ = AXUIElementSetMessagingTimeout(app, budgetInSeconds)

        // Read separately, so an app that names its window but hides its selection —
        // Chrome, in the probe — still yields the half it was willing to give.
        let title = element(app, kAXFocusedWindowAttribute).flatMap { string($0, kAXTitleAttribute) }
        let field = element(app, kAXFocusedUIElementAttribute)
        let selected = field.flatMap { string($0, kAXSelectedTextAttribute) }
        let caret = field.flatMap { field in
            // A negative length, which an app may report for no selection, would trap as a range.
            let selection = SurfaceProbe.selectedRange(field).map { range in
                range.location..<(range.location + max(range.length, 0))
            }
            return CaretText.around(string(field, kAXValueAttribute), selection: selection)
        }
        return FocusedWindow(
            title: title, selectedText: selected,
            precedingText: caret?.preceding, followingText: caret?.following)
    }

    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Checked by type ID immediately above. A conditional cast cannot express this:
        // Swift treats `as?` on a Core Foundation type as always succeeding, which
        // would silently accept a non-element.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ owner: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
