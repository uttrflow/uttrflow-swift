import AppKit
import ApplicationServices
import Foundation

/// Reads what the focused field publishes about itself, which is everything `FieldReading` decides from.
public enum FieldReader {
    /// Caps one message so an application that never answers releases this thread.
    private static let messagingTimeout: Float = 0.1

    /// Reads the field the user is typing in, or `nil` when nothing is focused.
    public static func read() -> FieldReading? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = app.bundleIdentifier,
            let field = focusedField(of: app.processIdentifier)
        else { return nil }

        guard let role = string(field, kAXRoleAttribute) else { return nil }
        return FieldReading(
            bundleIdentifier: bundleIdentifier,
            role: role,
            subrole: string(field, kAXSubroleAttribute),
            identifier: string(field, kAXIdentifierAttribute),
            placeholder: string(field, kAXPlaceholderValueAttribute),
            accessibilityDescription: string(field, kAXDescriptionAttribute),
            document: document(of: field)
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

    /// The page or the directory the field belongs to, which the window publishes when the field does not.
    private static func document(of field: AXUIElement) -> String? {
        if let own = string(field, kAXDocumentAttribute) { return own }
        guard let window = element(field, kAXWindowAttribute) else { return nil }
        return string(window, kAXDocumentAttribute)
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
