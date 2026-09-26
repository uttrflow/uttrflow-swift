import AppKit
import ApplicationServices
import Foundation
import UttrflowPredict

private import Synchronization

/// Wires the engine to macOS, off the coverage gate. See `Docs/context-accessibility.md`.
extension MacContextEngine {
    /// The engine as the app uses it.
    public convenience init() {
        self.init(
            readFrontmostApplication: { await MainActor.run { MacContextEngine.frontmostApplication() } },
            readFocusedWindow: { await MacContextEngine.focusedWindow(of: $0) },
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            observeActivations: MacContextEngine.observeActivations
        )
    }

    /// Notes every other application's activation, so the one behind Uttrflow is never a stale read's guess.
    static func observeActivations(
        _ report: @escaping @Sendable (FrontmostApplication) -> Void
    ) -> any Sendable {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            report(
                FrontmostApplication(
                    name: app.localizedName, bundleIdentifier: app.bundleIdentifier,
                    processIdentifier: app.processIdentifier))
        }
        return ActivationObserverToken(token: token)
    }

    /// `NSObjectProtocol` predates strict concurrency; this box is reviewed and never mutated after it is made.
    private struct ActivationObserverToken: @unchecked Sendable {
        let token: any NSObjectProtocol
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
        let expired = Expired()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                readQueue.async {
                    continuation.resume(
                        returning: read(application.processIdentifier, while: { !expired.isSet }))
                }
            }
        } onCancel: {
            expired.set()
        }
    }

    /// Concurrent, not serial: a read whose caller has stopped waiting must never hold up the one after it.
    private static let readQueue = DispatchQueue(
        label: "com.uttrflow.context", qos: .userInitiated, attributes: .concurrent)

    /// A cancellation flag a plain dispatch closure can see, since it runs outside the Task that started it.
    private final class Expired: Sendable {
        private let flag = Mutex(false)
        var isSet: Bool { flag.withLock { $0 } }
        func set() { flag.withLock { $0 = true } }
    }

    private static func read(
        _ processIdentifier: pid_t, while isWanted: @Sendable () -> Bool
    ) -> FocusedWindow {
        // Skipped before the first message when the caller gave up while this read was still queued.
        guard isWanted() else { return FocusedWindow() }
        let app = AXUIElementCreateApplication(processIdentifier)
        // Caps each message so an abandoned read does not outlive the budget the dictation waited for.
        _ = AXUIElementSetMessagingTimeout(app, budgetInSeconds)

        // Read separately, so an app that names its window but hides its selection still gives the half.
        let title = SurfaceProbe.element(app, kAXFocusedWindowAttribute, timeoutInSeconds: budgetInSeconds)
            .flatMap { SurfaceProbe.string($0, kAXTitleAttribute) }
        guard isWanted() else { return FocusedWindow(title: title) }
        let field = SurfaceProbe.element(app, kAXFocusedUIElementAttribute, timeoutInSeconds: budgetInSeconds)
        // Asked before any text is, so a field that hides what is typed is never read.
        if let field, isSecure(field) { return FocusedWindow(title: title, isSecure: true) }
        guard isWanted() else { return FocusedWindow(title: title) }
        let selected = field.flatMap { SurfaceProbe.string($0, kAXSelectedTextAttribute) }
        guard isWanted() else { return FocusedWindow(title: title, selectedText: selected) }
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
