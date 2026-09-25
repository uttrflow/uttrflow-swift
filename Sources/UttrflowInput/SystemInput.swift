import AppKit
import ApplicationServices
public import Foundation
public import UttrflowCore
import UttrflowPredict

private import Carbon
private import Synchronization

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

    /// The plain flavour beside the concealed marker, which clipboard managers read as a password.
    public func setConcealedText(_ text: String) {
        willWrite(text)
        // Built whole and written once, so no reader sees the words before the marker.
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.concealedType)
        clearForThisMacOnly()
        NSPasteboard.general.writeObjects([item])
    }

    /// The prefix of every nspasteboard.org marker type, which names a format and not an app.
    private static let convention = "org.nspasteboard."

    /// The marker type the clipboard-manager convention reserves for secrets.
    private static let concealedType = NSPasteboard.PasteboardType(convention + "ConcealedType")

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

/// The key code posted when no keyboard layout can be read, `v`'s position on a US QWERTY board.
private let fallbackVKeyCode: CGKeyCode = 9

/// Finds which key types a character under a keyboard layout. See `Docs/input-synthetic-keystrokes.md`.
enum LayoutKeyCode {
    /// The key code that types `character` under `layoutData`, or nil if no key on the board does.
    static func code(for character: UniChar, in layoutData: Data) -> CGKeyCode? {
        layoutData.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            for code in CGKeyCode(0)...CGKeyCode(127) {
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
                if status == noErr, length > 0, chars[0] == character { return code }
            }
            return nil
        }
    }
}

/// The key code for ⌘V, resolved from the layout the target interprets shortcuts with. See `Docs/input-synthetic-keystrokes.md`.
enum PasteKeyLayout {
    /// `v`, the character ⌘V is a shortcut for regardless of the key that types it.
    private static let vCharacter = UniChar(UnicodeScalar("v").value)

    /// The last resolved key code, readable from any thread without a Text Input Sources call.
    private static let cachedKeyCode = Mutex<CGKeyCode>(fallbackVKeyCode)

    /// Whether the change notification is already being watched, so starting twice still observes once.
    @MainActor private static var observing = false

    /// The cached key code for ⌘V, filled by `startObserving()` and kept current after that.
    static func vKeyCode() -> CGKeyCode {
        cachedKeyCode.withLock { $0 }
    }

    /// Fills the cache and keeps it filled, which every off-main reader depends on having been called.
    @MainActor
    static func startObserving() {
        guard !observing else { return }
        observing = true
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: nil
        ) { _ in
            // Back to the main queue explicitly, because HIToolbox asserts it and the poster is not it.
            DispatchQueue.main.async { MainActor.assumeIsolated { _ = refresh() } }
        }
        refresh()
    }

    /// Asks Text Input Sources what is selected and caches its ⌘V key code, the one place that calls TIS.
    @MainActor
    @discardableResult
    static func refresh() -> CGKeyCode {
        let code = readVKeyCode()
        cachedKeyCode.withLock { $0 = code }
        return code
    }

    /// The current layout's key code for `v`, or the ASCII-capable layout's when the current one has none.
    @MainActor
    private static func readVKeyCode() -> CGKeyCode {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let data = unicodeLayoutData(of: source),
            let code = LayoutKeyCode.code(for: vCharacter, in: data)
        {
            return code
        }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let data = unicodeLayoutData(of: source),
            let code = LayoutKeyCode.code(for: vCharacter, in: data)
        {
            return code
        }
        return fallbackVKeyCode
    }

    /// The raw layout table Text Input Sources holds for `source`, absent for input methods and the like.
    private static func unicodeLayoutData(of source: TISInputSource) -> Data? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    }
}

/// Presses ⌘V by posting keyboard events, which no test can assert anything about.
public struct CGEventKeystrokeSender: KeystrokeSender {
    public init() {}

    /// Starts tracking layout changes, so `sendPaste()` posts the key that types V under the current one.
    @MainActor
    public static func startObservingLayout() {
        PasteKeyLayout.startObserving()
    }

    public func sendPaste() throws(TextInsertionError) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw .insertionRejected(description: unmakeableKeystroke)
        }
        try postTaggedKeyPair(from: source, keyCode: PasteKeyLayout.vKeyCode()) { $0.flags = .maskCommand }
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

    /// Asks the focused element's role and names first, reading its value only when none of them says secure.
    public func focusedFieldIsSecure() -> Bool {
        guard let element = focusedElement() else { return false }
        return SecureField.isSecure(
            role: stringAttribute(kAXRoleAttribute, of: element),
            subrole: stringAttribute(kAXSubroleAttribute, of: element),
            identifier: stringAttribute(kAXIdentifierAttribute, of: element),
            placeholder: stringAttribute(kAXPlaceholderValueAttribute, of: element),
            description: stringAttribute(kAXDescriptionAttribute, of: element),
            value: { stringAttribute(kAXValueAttribute, of: element) })
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
