import AppKit
import ApplicationServices
import Foundation
import UttrflowPredict

/// Reads the focused field once, for everything the suggestion loop needs. See `Docs/predict.md`.
public enum FocusedFieldReader {
    /// Its own thread, because these calls block until the other application answers.
    private static let queue = DispatchQueue(label: "com.uttrflow.focused-field", qos: .userInitiated)

    /// One reading, off the main thread, or `nil` when nothing usable is focused.
    public static func read() async -> FocusedFieldSnapshot? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: snapshot()) }
        }
    }

    /// The same reading, synchronously, which only the queue above calls.
    static func snapshot() -> FocusedFieldSnapshot? {
        let started = DispatchTime.now().uptimeNanoseconds
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = app.bundleIdentifier,
            let field = SurfaceProbe.focusedField(of: app.processIdentifier),
            let role = string(field, kAXRoleAttribute)
        else { return nil }

        let subrole = string(field, kAXSubroleAttribute)
        let value = string(field, kAXValueAttribute)
        let range: CFRange? = axValue(field, kAXSelectedTextRangeAttribute, .cfRange)
        let secure = kAXSecureTextFieldSubrole as String
        let flipped = NSScreen.screens.first?.frame.maxY ?? 0

        return FocusedFieldSnapshot(
            bundleIdentifier: bundleIdentifier,
            applicationName: app.localizedName ?? bundleIdentifier,
            role: role,
            subrole: subrole,
            identifier: string(field, kAXIdentifierAttribute),
            placeholder: string(field, kAXPlaceholderValueAttribute),
            accessibilityDescription: string(field, kAXDescriptionAttribute),
            document: document(of: field),
            value: value,
            selection: range.map { NSRange(location: $0.location, length: $0.length) },
            caret: range.flatMap { caret(field, at: $0) }.map { flip($0, below: flipped) },
            window: windowFrame(of: field).map { flip($0, below: flipped) },
            pointSize: range.flatMap { pointSize(field, at: $0) },
            isSecure: role == secure || subrole == secure,
            isComposing: Composition.isComposing(
                markedText: markedText(field), inputSource: CompositionProbe.inputSourceKind()),
            readMicroseconds: Int((DispatchTime.now().uptimeNanoseconds - started) / 1000)
        )
    }

    /// What this field says about an input method's marked text. See `Docs/predict-ime.md`.
    private static func markedText(_ field: AXUIElement) -> MarkedText {
        guard let range: CFRange = axValue(field, "AXTextInputMarkedRange", .cfRange) else {
            return .unanswered
        }
        return range.length > 0 ? .present : .absent
    }

    /// Accessibility measures from the top of the primary screen; AppKit measures from the bottom.
    private static func flip(_ rect: CGRect, below primaryScreenMaxY: CGFloat) -> CGRect {
        SuggestionGeometry.fromAccessibility(rect, primaryScreenMaxY: primaryScreenMaxY)
    }

    /// The page or the directory the field belongs to, which the window publishes when the field does not.
    private static func document(of field: AXUIElement) -> String? {
        if let own = string(field, kAXDocumentAttribute) { return own }
        guard let window = element(field, kAXWindowAttribute) else { return nil }
        return string(window, kAXDocumentAttribute)
    }

    /// The window's rectangle, which is what the strip stands on when no caret can be read.
    private static func windowFrame(of field: AXUIElement) -> CGRect? {
        guard let window = element(field, kAXWindowAttribute),
            let origin: CGPoint = axValue(window, kAXPositionAttribute, .cgPoint),
            let size: CGSize = axValue(window, kAXSizeAttribute, .cgSize)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The insertion point's screen rectangle, without which no ghost can be drawn.
    private static func caret(_ field: AXUIElement, at range: CFRange) -> CGRect? {
        guard let answer = parameterized(field, kAXBoundsForRangeParameterizedAttribute, range),
            CFGetTypeID(answer) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        guard AXValueGetValue(unsafeDowncast(answer, to: AXValue.self), .cgRect, &rect),
            !rect.isNull
        else { return nil }
        return rect
    }

    /// The type size at the caret, so the ghost is set in the field's own font.
    private static func pointSize(_ field: AXUIElement, at range: CFRange) -> CGFloat? {
        let widened =
            range.length > 0 ? range : CFRange(location: max(range.location - 1, 0), length: 1)
        guard
            let answer = parameterized(
                field, kAXAttributedStringForRangeParameterizedAttribute, widened),
            let attributed = answer as? NSAttributedString, attributed.length > 0,
            let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        else { return nil }
        return font.pointSize
    }

    /// One `AXValue` attribute, unwrapped into the Core Graphics type it stands for.
    private static func axValue<T>(
        _ owner: AXUIElement, _ attribute: String, _ kind: AXValueType
    ) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let unwrapped = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { unwrapped.deallocate() }
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), kind, unwrapped) else {
            return nil
        }
        return unwrapped.pointee
    }

    private static func parameterized(
        _ field: AXUIElement, _ attribute: String, _ range: CFRange
    ) -> AnyObject? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var answer: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                field, attribute as CFString, parameter, &answer) == .success
        else { return nil }
        return answer
    }

    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ owner: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
