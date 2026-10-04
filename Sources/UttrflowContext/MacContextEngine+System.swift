import AppKit
import ApplicationServices
import Foundation
import UttrflowCore
import UttrflowPredict

private import Synchronization

/// Wires the engine to macOS, off the coverage gate. See `Docs/context-accessibility.md`.
extension MacContextEngine {
    /// The engine as the app uses it.
    public convenience init() {
        self.init(
            readFrontmostApplication: { MacContextEngine.frontmostApplication() },
            readFocusOwner: { await MacContextEngine.focusOwner(of: $0) },
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

    /// Identity, from NSWorkspace, read off the main actor as `UttrflowInput` reads it. See `Docs/context-budget.md`.
    static func frontmostApplication() -> FrontmostApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostApplication(
            name: app.localizedName,
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier
        )
    }

    /// The application that owns the focused element, from Accessibility on a thread of its own. See `Docs/insertion.md`.
    static func focusOwner(of frontmost: FrontmostApplication) async -> FrontmostApplication? {
        guard AXIsProcessTrusted() else { return nil }
        return await withCheckedContinuation { continuation in
            readQueue.async { continuation.resume(returning: owner(of: frontmost)) }
        }
    }

    /// The element kept by the same preference insertion applies, named by the process that holds it.
    private static func owner(of frontmost: FrontmostApplication) -> FrontmostApplication? {
        // Never set on the system-wide element: that is process-wide and would cut dictation's own writes short.
        let system = AXUIElementCreateSystemWide()
        let focused = FocusedElementPreference.choose(
            systemWide: SurfaceProbe.element(
                system, kAXFocusedUIElementAttribute, timeoutInSeconds: budgetInSeconds),
            systemWideRole: { SurfaceProbe.string($0, kAXRoleAttribute) },
            application: {
                let application = AXUIElementCreateApplication(frontmost.processIdentifier)
                _ = AXUIElementSetMessagingTimeout(application, budgetInSeconds)
                return SurfaceProbe.element(
                    application, kAXFocusedUIElementAttribute, timeoutInSeconds: budgetInSeconds)
            },
            applicationRole: { SurfaceProbe.string($0, kAXRoleAttribute) })
        guard let owner = focused.flatMap(SurfaceProbe.owner(of:)) else { return nil }
        guard owner != frontmost.processIdentifier else { return frontmost }
        guard let app = NSRunningApplication(processIdentifier: owner) else { return nil }
        return FrontmostApplication(
            name: app.localizedName, bundleIdentifier: app.bundleIdentifier, processIdentifier: owner)
    }

    /// Title and selection, from Accessibility on a thread of its own. See `Docs/context-budget.md`.
    static func focusedWindow(of application: FrontmostApplication) async -> FocusedWindow? {
        guard AXIsProcessTrusted() else { return nil }
        let expired = Expired()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                readQueue.async {
                    continuation.resume(
                        returning: read(application, while: { !expired.isSet }))
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
        _ application: FrontmostApplication, while isWanted: @Sendable () -> Bool
    ) -> FocusedWindow {
        // Skipped before the first message when the caller gave up while this read was still queued.
        guard isWanted() else { return FocusedWindow() }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        // Caps each message so an abandoned read does not outlive the budget the dictation waited for.
        _ = AXUIElementSetMessagingTimeout(app, budgetInSeconds)

        // Read separately, so an app that names its window but hides its selection still gives the half.
        let title = SurfaceProbe.element(app, kAXFocusedWindowAttribute, timeoutInSeconds: budgetInSeconds)
            .flatMap { SurfaceProbe.string($0, kAXTitleAttribute) }
        guard isWanted() else { return FocusedWindow(title: title) }
        guard
            let field = SurfaceProbe.element(
                app, kAXFocusedUIElementAttribute, timeoutInSeconds: budgetInSeconds)
        else { return FocusedWindow(title: title) }
        // The same names, selection and bounded value the suggestion read asks, so the secure order is decided once.
        let names = SurfaceProbe.names(of: field)
        if names.isDeclaredSecure { return FocusedWindow(title: title, isSecure: true) }
        guard isWanted() else { return FocusedWindow(title: title) }
        let resolvedSelection = SurfaceProbe.selection(field)
        if case .discontinuous = resolvedSelection { return FocusedWindow(title: title) }
        let range: CFRange? = if case .range(let range) = resolvedSelection { range } else { nil }
        let text = SurfaceProbe.text(of: field, names: names, at: range)
        if text.isSecure { return FocusedWindow(title: title, isSecure: true) }
        let selected = SurfaceProbe.selectedText(of: field, at: range)
        guard isWanted() else { return FocusedWindow(title: title, selectedText: selected) }
        let selection = text.selection.flatMap {
            AccessibilityRange.selection(location: $0.location, length: $0.length)
        }
        let caret =
            application.bundleIdentifier.map(TerminalApplications.contains) == true
            ? CaretText.inTerminal(text.value, selection: selection, windowTitle: title)
            : CaretText.around(text.value, selection: selection)
        let role = names.role
        let multiline =
            SurfaceProbe.boolean(field, "AXMultiline")
            ?? role.flatMap { role in
                switch role {
                case "AXTextArea": true
                case "AXTextField", "AXSearchField": false
                default: nil
                }
            }
        return FocusedWindow(
            title: title, selectedText: selected,
            precedingText: caret?.preceding, followingText: caret?.following,
            accessibilityRole: role, isMultiline: multiline, fieldLabel: names.label)
    }
}
