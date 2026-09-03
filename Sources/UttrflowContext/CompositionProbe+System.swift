import AppKit
import ApplicationServices
public import UttrflowPredict

private import Carbon
private import Synchronization

/// Reads whether an input method is mid-composition in the focused field. See `Docs/predict-ime.md`.
public enum CompositionProbe {
    /// The range an input method is composing into, which AppKit text views publish and little else does.
    private static let markedRangeAttribute = "AXTextInputMarkedRange"

    /// The last input source read on the main queue, because Text Input Sources traps on any other.
    private static let cachedInputSourceKind = Mutex<InputSourceKind>(.unknown)

    /// Whether the change notification is already being watched, so starting twice still observes once.
    @MainActor private static var observing = false

    /// Whether an input method is composing right now, from the field first and the input source second.
    public static func isComposing(of app: FrontmostApp) -> Bool {
        Composition.isComposing(markedText: markedText(of: app), inputSource: inputSourceKind())
    }

    /// What the focused field says about its marked text, which most fields decline to answer.
    public static func markedText(of app: FrontmostApp) -> MarkedText {
        guard AXIsProcessTrusted(),
            let field = SurfaceProbe.focusedField(of: app.processIdentifier)
        else { return .unanswered }

        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(field, markedRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return .unanswered }

        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range)
        else { return .unanswered }
        return range.length > 0 ? .present : .absent
    }

    /// The cached kind of the selected keyboard input source, readable from any thread without a TIS call.
    public static func inputSourceKind() -> InputSourceKind {
        cachedInputSourceKind.withLock { $0 }
    }

    /// Fills the cache and keeps it filled, which every off-main reader depends on having been called.
    @MainActor
    static func startObservingInputSource() {
        guard !observing else { return }
        observing = true
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: nil
        ) { _ in
            // Back to the main queue explicitly, because HIToolbox asserts it and the poster is not it.
            DispatchQueue.main.async { MainActor.assumeIsolated { _ = refreshInputSourceKind() } }
        }
        refreshInputSourceKind()
    }

    /// Asks Text Input Sources what is selected and caches it, the one place in the app that calls TIS.
    @MainActor
    @discardableResult
    public static func refreshInputSourceKind() -> InputSourceKind {
        let kind = readInputSourceKind()
        cachedInputSourceKind.withLock { $0 = kind }
        return kind
    }

    /// Whether the selected keyboard input source is a plain layout or something that can compose.
    @MainActor
    private static func readInputSourceKind() -> InputSourceKind {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
        else { return .unknown }

        let type = Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
        return type == kTISTypeKeyboardLayout as String ? .layout : .inputMethod
    }
}
