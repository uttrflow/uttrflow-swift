import AppKit
import ApplicationServices
public import UttrflowPredict

private import Carbon

/// Reads whether an input method is mid-composition in the focused field. See `Docs/predict-ime.md`.
public enum CompositionProbe {
    /// The range an input method is composing into, which AppKit text views publish and little else does.
    private static let markedRangeAttribute = "AXTextInputMarkedRange"

    /// Whether an input method is composing right now, from the field first and the input source second.
    public static func isComposing() -> Bool {
        Composition.isComposing(markedText: markedText(), inputSource: inputSourceKind())
    }

    /// What the focused field says about its marked text, which most fields decline to answer.
    public static func markedText() -> MarkedText {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
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

    /// Whether the selected keyboard input source is a plain layout or something that can compose.
    public static func inputSourceKind() -> InputSourceKind {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
        else { return .unknown }

        let type = Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
        return type == kTISTypeKeyboardLayout as String ? .layout : .inputMethod
    }
}
