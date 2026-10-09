import AppKit
import ApplicationServices
import Foundation
import UttrflowCore

private import Synchronization

/// Wires the engine to macOS, off the coverage gate. See `Docs/context-accessibility.md`.
extension MacContextEngine {
    /// The engine as the app uses it.
    public convenience init() {
        self.init(
            readFrontmostApplication: { MacContextEngine.frontmostApplication() },
            readFocusOwner: { await MacContextEngine.focusOwner(of: $0) },
            readFocusedWindow: { await MacContextEngine.focusedWindow(of: $0, into: $1) },
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            countInputs: { [inputs = InputCount(sinceLastInput: MacContextEngine.sinceKeyOrClick)] in
                inputs.value
            },
            observeActivations: MacContextEngine.observeActivations
        )
    }

    /// How long ago the session last saw a key pressed or a mouse button go down, asked without a monitor.
    static func sinceKeyOrClick() -> Duration {
        let seconds = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown].map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }
        return .seconds(seconds.min() ?? 0)
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
    static func focusedWindow(of application: FrontmostApplication, into sink: FocusedWindowSink) async {
        // Not gated on trust: without the grant the first batch answers `.notTrusted`, which the read banks.
        let expired = Expired()
        let started = ContinuousClock.now
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                readQueue.async {
                    read(application, started: started, into: sink, while: { !expired.isSet })
                    continuation.resume()
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

    /// Banks each answer as it lands, so a read the budget cuts short keeps the part it finished.
    private static func read(
        _ application: FrontmostApplication, started: ContinuousClock.Instant, into sink: FocusedWindowSink,
        while isWanted: @Sendable () -> Bool
    ) {
        // Skipped before the first message when the caller gave up while this read was still queued.
        guard isWanted() else { return }
        let app = FocusedFieldReader.AXNode(
            keepingTimeout: AXUIElementCreateApplication(application.processIdentifier))
        let isTerminal = application.bundleIdentifier.map(TerminalApplications.contains) == true
        let source = TreeWindowSource(
            tree: FocusedFieldReader.AXElementTree(), app: app, decode: .accessibility,
            cap: { _ = AXUIElementSetMessagingTimeout($0.element, timeLeft(since: started)) },
            identify: { node in
                SurfaceProbe.owner(of: node.element).map {
                    FieldIdentity(
                        processIdentifier: $0,
                        windowNumber: FocusedFieldReader.windowNumber(of: node.element),
                        element: Int(bitPattern: CFHash(node.element)))
                }
            })
        read(source, isTerminal: isTerminal, into: sink, while: isWanted)
    }
}

extension FieldAnswerDecoder<FocusedFieldReader.AXNode> {
    /// Accessibility's answers, each element left at the timeout its caller sets.
    static var accessibility: Self { decoding(as: FocusedFieldReader.AXNode.init(keepingTimeout:)) }

    /// Accessibility's answers, each element capped at the focused field's own timeout as it is decoded.
    static var capping: Self { decoding(as: { FocusedFieldReader.AXNode($0) }) }

    /// Checked by type ID, since `as?` on a Core Foundation type always succeeds.
    private static func decoding(as node: @escaping (AXUIElement) -> FocusedFieldReader.AXNode) -> Self {
        Self(
            element: { value in
                let object = value as AnyObject
                guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
                return node(unsafeDowncast(object, to: AXUIElement.self))
            },
            range: { SurfaceProbe.unwrap($0 as AnyObject, .cfRange) },
            point: { SurfaceProbe.unwrap($0 as AnyObject, .cgPoint) },
            size: { SurfaceProbe.unwrap($0 as AnyObject, .cgSize) },
            rect: { SurfaceProbe.unwrap($0 as AnyObject, .cgRect) })
    }
}
