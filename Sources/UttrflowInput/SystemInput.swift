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
}

/// What every failure to build a synthetic keystroke reports.
private let unmakeableKeystroke = "could not create the keystroke"

/// Posts one key-down and key-up marked as this app's own, after `prepare` has set up each.
private func postTaggedKeyPair(
    from source: CGEventSource, keyCode: CGKeyCode, prepare: (CGEvent) -> Void
) throws(TextInsertionError) {
    guard
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else { throw .insertionRejected(description: unmakeableKeystroke) }

    for event in [keyDown, keyUp] {
        prepare(event)
        SyntheticEvent.tag(event)
    }
    // The one pair that reaches another application. See `Docs/insertion.md`.
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

/// Presses ⌘V by posting keyboard events, which no test can assert anything about.
public struct CGEventKeystrokeSender: KeystrokeSender {
    /// Virtual key code for V, positional and so correct on any keyboard layout.
    private static let vKeyCode: CGKeyCode = 9

    public init() {}

    public func sendPaste() throws(TextInsertionError) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw .insertionRejected(description: unmakeableKeystroke)
        }
        try postTaggedKeyPair(from: source, keyCode: Self.vKeyCode) { $0.flags = .maskCommand }
    }
}

/// Types characters by posting key events that carry them, which no test can assert anything about.
public struct CGEventTypist: KeystrokeTyping {
    /// How many UTF-16 units one event may carry; longer strings are silently truncated by the system.
    private static let unitsPerEvent = 16

    /// Virtual key code for Delete, positional and so correct on any keyboard layout.
    private static let deleteKeyCode: CGKeyCode = 51

    public init() {}

    /// One press per character, because there is no bulk delete a synthetic keyboard can reach for.
    public func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        guard count > 0 else { return }
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw .insertionRejected(description: "could not create the keystroke")
        }
        for _ in 0..<count {
            // Flags cleared so a modifier the user is still holding cannot widen the delete.
            try postTaggedKeyPair(from: source, keyCode: Self.deleteKeyCode) { $0.flags = [] }
        }
    }

    public func type(_ text: String) throws(TextInsertionError) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw .insertionRejected(description: "could not create the keystroke")
        }
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: Self.unitsPerEvent) {
            let chunk = Array(units[start..<min(start + Self.unitsPerEvent, units.count)])
            try postTaggedKeyPair(from: source, keyCode: 0) { event in
                // Flags cleared so a modifier the user is still holding cannot make this a shortcut.
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            }
        }
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

    /// The `count` characters before the caret, when the field will report both its value and its caret.
    public func precedingText(_ count: Int) -> String? {
        guard
            count > 0, let element = focusedElement(),
            let value = stringAttribute(kAXValueAttribute, of: element),
            let range = rangeAttribute(kAXSelectedTextRangeAttribute, of: element)
        else { return nil }
        return BackwardSelection.text(in: value, endingAt: range.location, covering: count)
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

    /// Grows the selection back over `characters` first, so one write replaces them and undo sees one edit.
    func replaceSelection(
        precededBy characters: Int, with text: String
    ) throws(TextInsertionError) {
        guard characters > 0 else { return try replaceSelection(with: text) }
        let caret = try selectBackwards(characters)
        do {
            try replaceSelection(with: text)
        } catch {
            // A field that took the selection but refused the text is left as it was found, so the next route sees the caret, not a selection.
            _ = try? select(caret)
            throw error
        }
    }

    /// Moves the selection's start back over `characters` and answers with the selection as it was.
    private func selectBackwards(_ characters: Int) throws(TextInsertionError) -> CFRange {
        guard let whole = value(), let selection = selectedRange() else {
            throw .insertionRejected(description: "the field will not report its selection")
        }
        guard
            let widened = BackwardSelection.range(
                in: whole, endingAt: selection.location, covering: characters)
        else {
            throw .insertionRejected(description: "the field has too little text before the caret")
        }
        try select(
            CFRange(
                location: widened.lowerBound,
                length: selection.length + (selection.location - widened.lowerBound)))
        return selection
    }

    /// Sets the selection, which a field that hides its range refuses.
    private func select(_ range: CFRange) throws(TextInsertionError) {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else {
            throw .insertionRejected(description: "could not describe the selection")
        }
        let result = AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, value)
        guard result == .success else {
            throw .insertionRejected(
                description: "the field refused the selection (\(result.rawValue))")
        }
    }

    /// Where the caret is, in UTF-16 units, when the field will say.
    private func selectedRange() -> CFRange? {
        rangeAttribute(kAXSelectedTextRangeAttribute, of: element)
    }

    /// The field's whole contents, when it will say.
    private func value() -> String? {
        stringAttribute(kAXValueAttribute, of: element)
    }
}

/// The string an Accessibility attribute holds, or `nil` when the element will not say.
private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
    var current: AnyObject?
    guard
        AXUIElementCopyAttributeValue(element, name as CFString, &current) == .success
    else { return nil }
    return current as? String
}

/// The range an Accessibility attribute holds, or `nil` when the element will not say.
private func rangeAttribute(_ name: String, of element: AXUIElement) -> CFRange? {
    var current: AnyObject?
    guard
        AXUIElementCopyAttributeValue(element, name as CFString, &current) == .success,
        let value = current, CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }

    // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
    var range = CFRange()
    guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) else {
        return nil
    }
    return range
}
