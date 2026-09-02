import AppKit
import ApplicationServices
import Foundation

/// Reads what the focused text field says about itself. See `Docs/predict-probe.md`.
public enum SurfaceProbe {
    /// Caps one message so an app that never answers releases this thread.
    private static let messagingTimeout: Float = 0.1

    /// Reads the field the user is typing in, or `nil` when nothing is focused.
    public static func read() -> SurfaceCapability? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let started = DispatchTime.now().uptimeNanoseconds
        guard let field = focusedField(of: app.processIdentifier) else { return nil }

        let role = string(field, kAXRoleAttribute)
        let value = string(field, kAXValueAttribute)
        let range = selectedRange(field)
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1000)

        return SurfaceCapability(
            application: app.localizedName ?? app.bundleIdentifier ?? "unknown",
            role: role,
            locator: locator(field),
            reportsValue: value != nil,
            reportsCaretRect: range.flatMap { bounds(field, at: $0) } != nil,
            reportsTextStyle: range.flatMap { style(field, at: $0) } != nil,
            isSecure: isSecure(field, role: role),
            readMicroseconds: elapsed
        )
    }

    /// Asks system-wide first and the application second, because apps answer only one. See `Docs/insertion.md`.
    private static func focusedField(of pid: pid_t) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, messagingTimeout)
        if let field = element(system, kAXFocusedUIElementAttribute) { return field }

        let application = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
        return element(application, kAXFocusedUIElementAttribute)
    }

    /// Tells one field in an application from another, so two of the same role do not collapse into one.
    private static func locator(_ field: AXUIElement) -> String? {
        string(field, kAXIdentifierAttribute) ?? string(field, kAXPlaceholderValueAttribute)
            ?? string(field, kAXDescriptionAttribute)
    }

    /// Whether the field hides what is typed, which AppKit reports as a subrole and others as a role.
    private static func isSecure(_ field: AXUIElement, role: String?) -> Bool {
        let secure = kAXSecureTextFieldSubrole as String
        return role == secure || string(field, kAXSubroleAttribute) == secure
    }

    /// The caret as a range, which every parameterized read below is asked about.
    private static func selectedRange(_ field: AXUIElement) -> CFRange? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                field, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range)
        else { return nil }
        return range
    }

    /// The insertion point's screen rectangle, which decides whether a ghost can be drawn.
    private static func bounds(_ field: AXUIElement, at range: CFRange) -> CGRect? {
        guard let answer = parameterized(field, kAXBoundsForRangeParameterizedAttribute, range),
            CFGetTypeID(answer) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        guard AXValueGetValue(unsafeDowncast(answer, to: AXValue.self), .cgRect, &rect)
        else { return nil }
        return rect.isNull ? nil : rect
    }

    /// The font and colour at the caret, without which a ghost cannot match the line.
    private static func style(_ field: AXUIElement, at range: CFRange) -> NSAttributedString? {
        guard
            let answer = parameterized(
                field, kAXAttributedStringForRangeParameterizedAttribute, styled(range)),
            let attributed = answer as? NSAttributedString, attributed.length > 0
        else { return nil }
        return attributed.attribute(.font, at: 0, effectiveRange: nil) == nil ? nil : attributed
    }

    /// Widens an empty caret range to one character, which is what the style read needs.
    private static func styled(_ range: CFRange) -> CFRange {
        range.length > 0 ? range : CFRange(location: max(range.location - 1, 0), length: 1)
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
