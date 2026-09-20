import AppKit
import ApplicationServices
public import Foundation
public import UttrflowCore

/// The real clipboard, untestable by construction and so excluded from the coverage gate.
public struct SystemPasteboard: Pasteboard {
    /// Told what this app is about to write, so the watcher can tell it from a copy. See `Docs/insertion.md`.
    private let willWrite: @Sendable (String) -> Void
    /// Told the bytes a picture write puts there, which is what names it to the watcher.
    private let willWritePicture: @Sendable (Data) -> Void

    /// Takes the announcements the clipboard watcher needs, and by default makes none.
    public init(
        willWrite: @escaping @Sendable (String) -> Void = { _ in },
        willWritePicture: @escaping @Sendable (Data) -> Void = { _ in }
    ) {
        self.willWrite = willWrite
        self.willWritePicture = willWritePicture
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

    /// K4 — the picture flavour, announced by its bytes and kept off Universal Clipboard like every other write.
    public func setImage(_ data: Data) {
        willWritePicture(data)
        clearForThisMacOnly()
        NSPasteboard.general.setData(data, forType: .png)
    }

    /// Clears the pasteboard and keeps what goes on it next off Universal Clipboard. See `Docs/insertion.md`.
    private func clearForThisMacOnly() {
        NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)
    }
}

/// What every failure to build a synthetic keystroke reports.
private let unmakeableKeystroke = "could not create the keystroke"

/// Posts one tagged key-down and key-up, after `prepare` has set each up. See `Docs/input-synthetic-keystrokes.md`.
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
    /// How many UTF-16 units one event may carry; the system truncates a longer string in silence.
    private static let unitsPerEvent = 16

    /// Virtual key code for Delete, positional and so correct on any keyboard layout.
    private static let deleteKeyCode: CGKeyCode = 51

    public init() {}

    /// One press per character, because there is no bulk delete a synthetic keyboard can reach for.
    public func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        guard count > 0 else { return }
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw .insertionRejected(description: unmakeableKeystroke)
        }
        for _ in 0..<count {
            // Flags cleared so a modifier the user is still holding cannot widen the delete.
            try postTaggedKeyPair(from: source, keyCode: Self.deleteKeyCode) { $0.flags = [] }
        }
    }

    public func type(_ text: String) throws(TextInsertionError) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw .insertionRejected(description: unmakeableKeystroke)
        }
        for chunk in UTF16Chunking.chunks(of: text, limit: Self.unitsPerEvent) {
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

    /// The same in-process read `isSelfFrontmost` makes, so naming the destination costs no message to another app.
    public func frontmostApplication() -> InsertionDestination? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return InsertionDestination(
            applicationName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier)
    }

    /// The focused element, asked system-wide then per-application. See `Docs/insertion.md`.
    private func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        // The timeout goes on the element itself: set on the system-wide element it is process-wide, and a suggestion read could lower it mid-insertion (#887).
        let system = AXUIElementCreateSystemWide()
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
        let field = unsafeDowncast(element, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(field, Self.messagingTimeout)
        return field
    }

    /// The `count` characters before the caret, when the field will report both its value and its caret.
    public func precedingText(_ count: Int) -> String? {
        guard
            count > 0, let element = focusedElement(),
            let value = stringAttribute(kAXValueAttribute, of: element),
            let range = rangeAttribute(kAXSelectedTextRangeAttribute, of: element)
        else { return nil }
        return BackwardSelection.text(in: value, endingAt: range.location, exactly: count)
    }

    /// As much as the field holds before the caret, so a field shorter than the request is still read.
    public func tail(upTo count: Int) -> FieldTail {
        guard
            count > 0, let element = focusedElement(),
            let value = stringAttribute(kAXValueAttribute, of: element),
            let range = rangeAttribute(kAXSelectedTextRangeAttribute, of: element),
            let tail = BackwardSelection.tail(in: value, endingAt: range.location, upTo: count)
        else { return .unreadable }
        return .text(tail)
    }

    public func focusedTextField() -> (any FocusedTextField)? {
        guard let candidate = focusedElement() else { return nil }

        // A field that will not report its selection will not accept one either.
        var selection: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                candidate, kAXSelectedTextAttribute as CFString, &selection) == .success
        else { return nil }

        return SelectionWriter(field: AXSelectionAttributes(element: candidate))
    }
}

/// A focused field's selection attributes, holding an `AXUIElement` that is safe to pass between threads.
private struct AXSelectionAttributes: SelectionAttributes, @unchecked Sendable {
    /// The focused element this reads and writes.
    let element: AXUIElement

    func value() -> String? {
        stringAttribute(kAXValueAttribute, of: element)
    }

    func selectedRange() -> CFRange? {
        rangeAttribute(kAXSelectedTextRangeAttribute, of: element)
    }

    func setSelectedText(_ text: String) -> AXError {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
    }

    /// A range that cannot be described is reported as an illegal argument, which the writer refuses.
    func setSelectedRange(_ range: CFRange) -> AXError {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
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
