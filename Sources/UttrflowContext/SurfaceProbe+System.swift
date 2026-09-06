import AppKit
import ApplicationServices
import Foundation

/// Reads other applications through Accessibility, from one attribute to a whole field's capabilities. See `Docs/predict-probe.md`.
public enum SurfaceProbe {
    /// Caps one message so an app that never answers releases this thread.
    private static let messagingTimeout: Float = 0.1

    /// Reads the field the user is typing in, or `nil` when nothing is focused; identity comes from the main thread.
    public static func read(of app: FrontmostApp) -> SurfaceCapability? {
        guard AXIsProcessTrusted() else { return nil }

        let started = DispatchTime.now().uptimeNanoseconds
        guard let field = focusedField(of: app.processIdentifier) else { return nil }

        let role = string(field, kAXRoleAttribute)
        let value = string(field, kAXValueAttribute)
        let range = selectedRange(field)
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1000)

        return SurfaceCapability(
            application: app.name,
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
    static func focusedField(of pid: pid_t) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, messagingTimeout)
        let systemWide = element(system, kAXFocusedUIElementAttribute)
        // While a browser editor is typed into, the system names the word under the caret; the application still names the field.
        if let field = systemWide, FocusedFieldSnapshot.isTextEntry(string(field, kAXRoleAttribute)) {
            return field
        }
        let application = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let own = element(application, kAXFocusedUIElementAttribute)
        if let field = own, FocusedFieldSnapshot.isTextEntry(string(field, kAXRoleAttribute)) { return field }
        return systemWide ?? own
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
    static func selectedRange(_ field: AXUIElement) -> CFRange? {
        value(field, kAXSelectedTextRangeAttribute, .cfRange)
    }

    /// The screen rectangle Accessibility reports for one text range, which decides whether a ghost can be drawn.
    static func bounds(_ field: AXUIElement, at range: CFRange) -> CGRect? {
        let rect: CGRect? = unwrap(
            parameterized(field, kAXBoundsForRangeParameterizedAttribute, range), .cgRect)
        return rect.flatMap { $0.isNull ? nil : $0 }
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

    /// One attribute read with a range for a parameter, which is how a field is asked about part of its text.
    static func parameterized(
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

    /// One attribute that is itself an element, capped at the given timeout where the caller has one to impose.
    static func element(
        _ owner: AXUIElement, _ attribute: String, timeoutInSeconds: Float? = nil
    ) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let element = unsafeDowncast(value, to: AXUIElement.self)
        if let timeoutInSeconds { _ = AXUIElementSetMessagingTimeout(element, timeoutInSeconds) }
        return element
    }

    /// One attribute read as text, or nothing where the element answers something else.
    static func string(_ owner: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// One `AXValue` attribute, unwrapped into the Core Graphics type it stands for.
    static func value<T>(_ owner: AXUIElement, _ attribute: String, _ kind: AXValueType) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return unwrap(value, kind)
    }

    /// One `AXValue`, already fetched, unwrapped into the Core Graphics type it stands for.
    static func unwrap<T>(_ value: AnyObject?, _ kind: AXValueType) -> T? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let unwrapped = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { unwrapped.deallocate() }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), kind, unwrapped) else {
            return nil
        }
        return unwrapped.pointee
    }
}
