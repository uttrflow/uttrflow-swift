import AppKit
import ApplicationServices
import Foundation
import UttrflowPredict

/// Wires the engine to macOS, off the coverage gate. See `Docs/context-accessibility.md`.
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

    /// Title and selection, from Accessibility on a thread of its own. See `Docs/context-budget.md`.
    static func focusedWindow(of application: FrontmostApplication) async -> FocusedWindow? {
        guard AXIsProcessTrusted() else { return nil }
        return await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: read(application.processIdentifier))
            }
        }
    }

    private static let readQueue = DispatchQueue(label: "com.uttrflow.context", qos: .userInitiated)

    private static func read(_ processIdentifier: pid_t) -> FocusedWindow {
        let app = AXUIElementCreateApplication(processIdentifier)
        // Caps each message so an abandoned read does not outlive the budget the dictation waited for.
        _ = AXUIElementSetMessagingTimeout(app, budgetInSeconds)

        // Read separately, so an app that names its window but hides its selection still gives the half.
        let title = SurfaceProbe.element(app, kAXFocusedWindowAttribute, timeoutInSeconds: budgetInSeconds)
            .flatMap { SurfaceProbe.string($0, kAXTitleAttribute) }
        let field = SurfaceProbe.element(app, kAXFocusedUIElementAttribute, timeoutInSeconds: budgetInSeconds)
        // Asked before any text is, so a field that hides what is typed is never read.
        if let field, isSecure(field) { return FocusedWindow(title: title, isSecure: true) }
        let selected = field.flatMap { SurfaceProbe.string($0, kAXSelectedTextAttribute) }
        let caret = field.flatMap { field in
            let selection = SurfaceProbe.selectedRange(field).flatMap { range in
                AccessibilityRange.selection(location: range.location, length: range.length)
            }
            return CaretText.around(SurfaceProbe.string(field, kAXValueAttribute), selection: selection)
        }
        return FocusedWindow(
            title: title, selectedText: selected,
            precedingText: caret?.preceding, followingText: caret?.following)
    }

    /// Whether the field declares itself secure, or reads back as nothing but mask characters.
    static func isSecure(_ field: AXUIElement) -> Bool {
        SecureField.isSecure(
            role: SurfaceProbe.string(field, kAXRoleAttribute),
            subrole: SurfaceProbe.string(field, kAXSubroleAttribute),
            identifier: SurfaceProbe.string(field, kAXIdentifierAttribute),
            placeholder: SurfaceProbe.string(field, kAXPlaceholderValueAttribute),
            description: SurfaceProbe.string(field, kAXDescriptionAttribute),
            value: { SurfaceProbe.string(field, kAXValueAttribute) })
    }
}
