public import ApplicationServices
import Foundation
import UttrflowCore

/// Reads other applications through Accessibility, from one attribute to a whole field's capabilities. See `Docs/predict-probe.md`.
public enum SurfaceProbe {
    /// Caps one message so an app that never answers releases this thread.
    private static let messagingTimeout: Float = 0.1

    /// The suggestion loop's own reading of the focused field, so the capability table says what the feature will do.
    public static func read(of app: FrontmostApp) -> SurfaceCapability? {
        FocusedFieldReader.snapshot(app: app)?.capability
    }

    /// Asks system-wide first and the application second, because apps answer only one. See `Docs/insertion.md`.
    static func focusedField(of processIdentifier: pid_t) -> AXUIElement? {
        guard processIdentifier != getpid() else { return nil }
        // Never set on the system-wide element: that is process-wide and would cut dictation's own writes short (#887).
        let system = AXUIElementCreateSystemWide()
        let systemWide = element(system, kAXFocusedUIElementAttribute, timeoutInSeconds: messagingTimeout)
            .flatMap { field in owns(owner(of: field), processIdentifier) ? field : nil }
        return FocusedElementPreference.choose(
            systemWide: systemWide, systemWideRole: { string($0, kAXRoleAttribute) },
            application: {
                let application = AXUIElementCreateApplication(processIdentifier)
                _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)
                return element(application, kAXFocusedUIElementAttribute, timeoutInSeconds: messagingTimeout)
            },
            applicationRole: { string($0, kAXRoleAttribute) })
    }

    /// Whether a focused element's owner is the requested application and not Uttrflow's own nonactivating panel.
    static func owns(
        _ owner: pid_t?, _ processIdentifier: pid_t, current: pid_t = getpid()
    ) -> Bool {
        owner == processIdentifier && processIdentifier != current
    }

    /// The process that holds an element, or nothing where Accessibility will not say.
    static func owner(of field: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(field, &pid) == .success ? pid : nil
    }

    /// The caret as a range, which every parameterized read below is asked about.
    static func selectedRange(_ field: AXUIElement) -> CFRange? {
        guard case .range(let range) = selection(field) else { return nil }
        return range
    }

    /// The focused field's selection, refusing to guess at a multi-range caret.
    static func selection(_ field: AXUIElement) -> AccessibilitySelection {
        let plural = attribute(field, kAXSelectedTextRangesAttribute)
        if let ranges = plural as? [AnyObject], ranges.count > 1 {
            return .discontinuous
        }
        let pluralRanges = (plural as? [AnyObject])?.compactMap { unwrap($0, .cfRange) as CFRange? }
        return AccessibilitySelection.resolve(
            singular: value(field, kAXSelectedTextRangeAttribute, .cfRange), plural: pluralRanges,
            textLength: integer(field, kAXNumberOfCharactersAttribute))
    }

    /// What names the field, asked in one message: its role and the four names it may publish for itself.
    public static func names(of field: AXUIElement) -> FieldNames {
        FocusedFieldRead.names(
            of: FocusedFieldReader.AXNode(keepingTimeout: field), in: FocusedFieldReader.AXElementTree())
    }

    /// The one read of a focused field's value, never fetched from a declared secure field nor copied whole when long.
    static func text(of field: AXUIElement, names: FieldNames, at range: CFRange?) -> FieldText {
        FocusedFieldRead.text(
            of: FocusedFieldReader.AXNode(keepingTimeout: field), in: FocusedFieldReader.AXElementTree(),
            names: names, at: range.map { NSRange(location: $0.location, length: $0.length) })
    }

    /// The selection's opening stretch, read by range so a selected document is never copied whole.
    static func selectedText(of field: AXUIElement, at range: CFRange?) -> String? {
        FocusedFieldRead.selectedText(
            of: FocusedFieldReader.AXNode(keepingTimeout: field), in: FocusedFieldReader.AXElementTree(),
            at: range.map { NSRange(location: $0.location, length: $0.length) })
    }

    /// The field's whole value under the shared secure-check order, or nil when secure, unknown or too long.
    public static func readableValue(of field: AXUIElement) -> String? {
        let names = names(of: field)
        guard !names.isSecureOrUnknown else { return nil }
        guard let count = integer(field, kAXNumberOfCharactersAttribute),
            count <= ValueWindow.unitsBefore + ValueWindow.unitsAfter
        else { return nil }
        let read = text(of: field, names: names, at: CFRange(location: 0, length: 0))
        guard let value = read.value else { return nil }
        return names.isSecure(value: { value }) ? nil : value
    }

    /// The screen rectangle Accessibility reports for one text range, which decides whether a ghost can be drawn.
    static func bounds(_ field: AXUIElement, at range: CFRange) -> CGRect? {
        let rect: CGRect? = unwrap(
            parameterized(field, kAXBoundsForRangeParameterizedAttribute, range), .cgRect)
        return rect.flatMap { $0.isNull ? nil : $0 }
    }

    /// One attribute read with a range for a parameter, which is how a field is asked about part of its text.
    static func parameterized(
        _ field: AXUIElement, _ attribute: String, _ range: CFRange
    ) -> AnyObject? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        return parameterized(field, attribute, parameter)
    }

    /// One attribute read with any parameter, such as a text marker or an element.
    static func parameterized(_ field: AXUIElement, _ attribute: String, _ parameter: AnyObject) -> AnyObject?
    {
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

    /// One attribute read as a whole number, or nothing where the element answers something else.
    static func integer(_ owner: AXUIElement, _ attribute: String) -> Int? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return (value as? NSNumber)?.intValue
    }

    /// One attribute read as a boolean, or nothing where the element answers something else.
    static func boolean(_ owner: AXUIElement, _ attribute: String) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success
        else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    /// One `AXValue` attribute, unwrapped into the Core Graphics type it stands for.
    static func value<T>(_ owner: AXUIElement, _ attribute: String, _ kind: AXValueType) -> T? {
        unwrap(self.attribute(owner, attribute), kind)
    }

    /// One attribute returned as an object, or nothing when the element will not say.
    private static func attribute(_ owner: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
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
