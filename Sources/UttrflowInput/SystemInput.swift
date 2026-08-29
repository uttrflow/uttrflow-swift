import AppKit
import ApplicationServices
import Foundation
public import UttrflowCore

/// The real clipboard.
///
/// Untestable by construction — it is the machine's own clipboard, shared with every
/// other app. Excluded from the coverage gate; everything that decides *when* to touch
/// it is tested against a substitute.
public struct SystemPasteboard: Pasteboard {
    /// Told immediately before every write this app makes to the clipboard.
    ///
    /// Exists so the clipboard watcher can tell Uttrflow's own writes from the user
    /// copying something. Pasting a clip puts it on the clipboard and never takes it
    /// back — the paste engine explains why — so without this the watcher sees a change
    /// it has no way to attribute, files the clip a second time, and moves it to the top
    /// of the panel every time it is used.
    ///
    /// A closure rather than a reference to the watcher, because this module knows
    /// nothing about clipboard history and should not start now: the app owns both ends
    /// and ties them together. Empty by default, so every existing caller is unaffected.
    private let willWrite: @Sendable () -> Void

    public init(willWrite: @escaping @Sendable () -> Void = {}) {
        self.willWrite = willWrite
    }

    public func text() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// E2 — the plain flavour always, the formatted one beside it when the clip has one.
    public func setText(_ text: String, richText: String?) {
        willWrite()
        clearForThisMacOnly()
        NSPasteboard.general.setString(text, forType: .string)
        if let richText { NSPasteboard.general.setString(richText, forType: .html) }
    }

    public func setText(_ text: String) {
        // Before the clear, not between it and `setString`: clearing is itself what moves
        // the change count, so an announcement made after it would arrive too late to
        // describe the change it is about.
        willWrite()
        clearForThisMacOnly()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Clears the pasteboard, and asks macOS to keep what goes on it next off Universal
    /// Clipboard.
    ///
    /// This is the paste route — the second of three insertion strategies, and the one
    /// that runs whenever the Accessibility route cannot write into the focused element,
    /// which is the common case in Electron apps and many web apps. So it is not an edge:
    /// it is how a large share of dictations reach the caret.
    ///
    /// `clearContents()` leaves the default, and the default is that everything written
    /// here is offered to every other Apple device signed into the same account. A
    /// product whose entire claim is that your words do not leave this Mac was, on that
    /// path, sending the finished transcript to the user's iPhone. `.currentHostOnly` is
    /// the one line that stops it.
    private func clearForThisMacOnly() {
        NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)
    }

    public func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }
}

/// Presses ⌘V by posting keyboard events.
///
/// Excluded from the coverage gate: it drives the window server, and there is nothing
/// to assert about it that is not simply "macOS did what we asked".
public struct CGEventKeystrokeSender: KeystrokeSender {
    /// Virtual key code for V on every keyboard layout — the code is positional, not
    /// the letter, so this is correct on non-QWERTY layouts too.
    private static let vKeyCode: CGKeyCode = 9

    public init() {}

    public func sendPaste() throws(TextInsertionError) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        // `.hidSystemState` and `.cghidEventTap` below are the pair that reaches another
        // application. The previous spelling — a combined-session source posted to
        // `.cgAnnotatedSessionEventTap` — creates a perfectly valid event that the target
        // never sees, and nothing reports an error: `post` returns no status. The paste
        // then "succeeded", and 250ms later the borrowed clipboard was put back over the
        // dictation, so the words were in the document, the clipboard and nowhere else —
        // exactly what a user sees as "it just does not work".
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

/// The focused text field, found through the Accessibility API.
///
/// Excluded from the coverage gate: it can only be exercised against a real focused
/// window. What it must never do — touch anything outside the selection — is
/// guaranteed by ``FocusedTextField`` offering nothing else, and tested there.
public struct AXAccessibilityFocus: AccessibilityFocus {
    public init() {}

    /// How long any one Accessibility message may take before it is given up on.
    ///
    /// Generous next to the context engine's 100 ms, because this read is the dictation
    /// rather than a nicety alongside it: giving up too eagerly costs the user their
    /// words, where the context engine giving up costs a spelling.
    ///
    /// But it must be bounded, and was not. These calls are synchronous and run on the
    /// pipeline's own thread, so a focused app that has quit, beachballed or gone to
    /// sleep held the pipeline in `.tidying` for the system default — `isBusy` the whole
    /// time, which means no further dictation could start either. The context engine
    /// already went to the trouble of a timeout for the *less* important read; the path
    /// that actually delivers the words did not.
    private static let messagingTimeout: Float = 2

    /// Anything focused at all, without asking it to report a selection.
    public func hasFocusedElement() -> Bool { focusedElement() != nil }

    public func isSelfFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
    }

    /// The focused element, asked for two different ways because neither alone works
    /// everywhere.
    ///
    /// `AXUIElementCreateSystemWide()` is the canonical answer and the one that works
    /// across the widest range of applications — but it returns nothing at all when the
    /// caller has no application context, which is why a command-line probe of this code
    /// reports "nothing focused" no matter what is on screen. Chasing that measurement
    /// is how the per-application query below came to be here on its own, and the
    /// per-application query is the weaker of the two: several applications answer
    /// `kAXFocusedUIElementAttribute` on the system-wide element and not on their own.
    ///
    /// So both, in that order. The cost of the fallback is one extra Accessibility
    /// round trip in the case that was already failing.
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

        // Checked by type ID immediately above. A conditional cast cannot express this:
        // Swift treats `as?` on a Core Foundation type as always succeeding.
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

/// Writes into one focused field.
///
/// `AXUIElement` is a Core Foundation type without a `Sendable` conformance, but it is
/// an opaque handle to a window-server object and is safe to pass between threads. The
/// unchecked conformance states that in one place.
private struct AXTextField: FocusedTextField, @unchecked Sendable {
    let element: AXUIElement

    func replaceSelection(with text: String) throws(TextInsertionError) {
        // Read first, so the write can be checked. Not every field answers, and one that
        // does not is simply trusted — this is a verification, not a precondition.
        let before = value()

        // Setting the selected text replaces exactly what is selected, and inserts at
        // the caret when nothing is. There is no call here that could reach further.
        let result = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard result == .success else {
            throw .insertionRejected(description: "the field refused the text (\(result.rawValue))")
        }

        // A success that changed nothing is the failure this exists to catch. Electron
        // applications — Claude's own desktop app is one — publish a focused text field,
        // accept a write to its selected text, answer `.success`, and do nothing at all.
        // Believing the return value meant the coordinator stopped here, so the words
        // never reached the paste below and never reached the clipboard either: the user
        // saw the dictation on screen and had nothing to paste. Reporting it as a refusal
        // lets the fallback do its job.
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
