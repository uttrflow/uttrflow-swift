import AppKit
import ApplicationServices
import Foundation
public import UttrflowCore

/// The real clipboard, untestable by construction and so excluded from the coverage gate.
public struct SystemPasteboard: Pasteboard {
    /// Told what this app is about to write, so the watcher can tell it from a copy. See `Docs/insertion.md`.
    private let willWrite: @Sendable (String?) -> Void

    /// - Parameter willWrite: Told what is about to go on the clipboard, before it does.
    public init(willWrite: @escaping @Sendable (String?) -> Void = { _ in }) {
        self.willWrite = willWrite
    }

    public func text() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// E2 — the plain flavour always, the formatted one beside it when the clip has one.
    public func setText(_ text: String, richText: String?) {
        willWrite(text)
        clearForThisMacOnly()
        NSPasteboard.general.setString(text, forType: .string)
        if let richText { NSPasteboard.general.setString(richText, forType: .html) }
    }

    public func setText(_ text: String) {
        // Before the clear, which is itself what moves the change count.
        willWrite(text)
        clearForThisMacOnly()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Clears the pasteboard and keeps what goes on it next off Universal Clipboard. See `Docs/insertion.md`.
    private func clearForThisMacOnly() {
        NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)
    }

    public func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }
}

/// Presses ⌘V by posting keyboard events, which no test can assert anything about.
public struct CGEventKeystrokeSender: KeystrokeSender {
    /// Virtual key code for V, positional and so correct on any keyboard layout.
    private static let vKeyCode: CGKeyCode = 9

    public init() {}

    public func sendPaste() throws(TextInsertionError) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        // The one pair that reaches another application. See `Docs/insertion.md`.
        guard let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else { throw .insertionRejected(description: "could not create the keystroke") }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

/// The focused text field, found through the Accessibility API against a real window.
public struct AXAccessibilityFocus: AccessibilityFocus {
    public init() {}

    /// How long one Accessibility message may take, generous because it is the dictation itself.
    private static let messagingTimeout: Float = 2

    /// Anything focused at all, without asking it to report a selection.
    public func hasFocusedElement() -> Bool { focusedElement() != nil }

    public func isSelfFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
    }

    /// The focused element, asked system-wide then per-application. See `Docs/insertion.md`.
    private func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        if let element = focusedElement(of: system) { return element }

        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(frontmost.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        return focusedElement(of: application)
    }

    private func focusedElement(of parent: AXUIElement) -> AXUIElement? {
        var focused: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                parent, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }

        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        return unsafeDowncast(element, to: AXUIElement.self)
    }

    public func focusedTextField() -> (any FocusedTextField)? {
        guard let candidate = focusedElement() else { return nil }

        // A field that will not report its selection will not accept one either.
        var selection: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                candidate, kAXSelectedTextAttribute as CFString, &selection) == .success
        else { return nil }

        return AXTextField(element: candidate)
    }
}

/// Writes into one focused field, holding an `AXUIElement` that is safe to pass between threads.
private struct AXTextField: FocusedTextField, @unchecked Sendable {
    let element: AXUIElement

    func replaceSelection(with text: String) throws(TextInsertionError) {
        // Read first so the write can be checked; a field that will not answer is trusted.
        let before = value()

        // Replaces the selection, or inserts at the caret when there is none.
        let result = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard result == .success else {
            throw .insertionRejected(description: "the field refused the text (\(result.rawValue))")
        }

        // A success that changed nothing is the failure this catches. See `Docs/insertion.md`.
        if let before, let after = value(), before == after, !text.isEmpty {
            throw .insertionRejected(
                description: "the field accepted the text and did not change")
        }
    }

    /// The field's whole contents, when it will say.
    private func value() -> String? {
        var current: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &current)
                == .success
        else { return nil }
        return current as? String
    }
}
