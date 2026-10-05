public import UttrflowCore

/// The text field the user is typing in, reduced to the two writes insertion needs. See `Docs/predict-accept.md`.
public protocol FocusedTextField: Sendable {
    /// Replaces the selection, or inserts at the caret; returns only once the caret is seen collapsed after the words.
    func replaceSelection(with text: String) throws(TextInsertionError)

    /// Replaces the selection *and* `replaced` before it, having confirmed that is what is there; only a completion asks.
    func replaceSelection(
        replacing replaced: String, with text: String
    ) throws(TextInsertionError)
}

extension FocusedTextField {
    /// A field that cannot select backwards refuses, so the keystroke route takes the replacement instead.
    public func replaceSelection(
        replacing replaced: String, with text: String
    ) throws(TextInsertionError) {
        guard replaced.isEmpty else {
            throw .insertionRejected(description: "the field cannot select backwards")
        }
        try replaceSelection(with: text)
    }
}

/// Finds the text field the user is typing in.
public protocol AccessibilityFocus: Sendable {
    /// The focused text field, or `nil` when what is focused cannot take text.
    func focusedTextField() -> (any FocusedTextField)?

    /// The field owned by `destination`, or `nil` when its owner cannot be verified.
    func focusedTextField(in destination: InsertionDestination) -> (any FocusedTextField)?

    /// Whether anything at all is focused that could take a paste, which many fields allow while refusing a selection read.
    func hasFocusedElement() -> Bool

    /// Whether Uttrflow itself is the application in front, in which case nothing may be typed or pasted.
    func isSelfFrontmost() -> Bool

    /// The `count` characters immediately before the caret, or `nil` when the field will not say.
    func precedingText(_ count: Int) -> String?

    /// As much of the text before the caret as there is, up to `count`, or that the field will not say.
    func tail(upTo count: Int) -> FieldTail

    /// The containing window and tail from one focused element read.
    func windowNumberAndTail(upTo count: Int) -> (windowNumber: UInt32?, tail: FieldTail)

    /// The bounded accept-path read, including the secure-field check.
    func acceptanceWindowNumberAndTail(upTo count: Int) -> (windowNumber: UInt32?, tail: FieldTail)

    /// The containing window of the field that will receive an insertion.
    func focusedWindowNumber() -> UInt32?

    /// The containing window rechecked with the accept-path timeout.
    func acceptanceFocusedWindowNumber() -> UInt32?

    /// The application owning the focused element, which is where a write lands. See `Docs/insertion.md`.
    func focusedApplication() -> InsertionDestination?

    /// Whether the focused field hides what is typed, asked without reading a declared secure field's value.
    func focusedFieldIsSecure() -> Bool

    /// The focused field and its caret, or `nil` when it is secure, has a selection or will not say.
    func focusedFieldPlace() -> FieldPlace?

    /// The focused element, secure or not, or `nil` when it cannot be told apart from another.
    func focusedFieldIdentity() -> FieldIdentity?

    /// Whether macOS lets this process drive other apps, read when an insertion fails so the cause is named.
    func isTrusted() -> Bool

    /// What kind of element has focus, so typing never lands on a control whose keys are commands.
    func focusedElementKind() -> FocusedElementKind
}

/// Keeps "nothing published" apart from "a control that is not a text field", which the typed route treats differently.
public enum FocusedElementKind: Sendable, Equatable {
    /// The application publishes no focused element, as a bundled-browser composer can while still taking typing.
    case unpublished
    /// A focused element whose role is one text is entered into.
    case textEntry
    /// A focused element of any other role, such as a page body, a list or a file browser.
    case control

    /// Classifies an element by its role, or `unpublished` when there is no element.
    public static func of(role: String?, isPublished: Bool) -> Self {
        guard isPublished else { return .unpublished }
        return FocusedElementPreference.isTextEntry(role) ? .textEntry : .control
    }
}

extension AccessibilityFocus {
    /// Implementations without owner checks cannot safely target a captured application.
    public func focusedTextField(in destination: InsertionDestination) -> (any FocusedTextField)? { nil }

    /// Implementations that cannot read a role report nothing published, the case typing has always been allowed.
    public func focusedElementKind() -> FocusedElementKind { .unpublished }
}

/// What a field says about the text before its caret, keeping "too short" apart from "will not say".
public enum FieldTail: Sendable, Equatable {
    /// Everything before the caret, up to what was asked for; shorter than that means the field is shorter.
    case text(String)
    /// The field reports neither its value nor its caret.
    case unreadable
}

extension AccessibilityFocus {
    /// Most fields on the typed route cannot be read, so the guard falls back to the cap alone.
    public func precedingText(_ count: Int) -> String? { nil }

    /// The same default: a field that will not report its value will not report its tail either.
    public func tail(upTo count: Int) -> FieldTail { .unreadable }

    /// A reader without a window-aware API cannot prove the field belongs to the drawn window.
    public func windowNumberAndTail(upTo count: Int) -> (windowNumber: UInt32?, tail: FieldTail) {
        (nil, tail(upTo: count))
    }

    /// Keeps fake and alternate readers secure while reusing their window-aware tail.
    public func acceptanceWindowNumberAndTail(upTo count: Int) -> (windowNumber: UInt32?, tail: FieldTail) {
        guard !focusedFieldIsSecure() else { return (nil, .unreadable) }
        return windowNumberAndTail(upTo: count)
    }

    /// A reader without a window-aware API cannot prove where an insertion will land.
    public func focusedWindowNumber() -> UInt32? { nil }

    /// Uses the regular window answer when no accept-specific timeout is needed.
    public func acceptanceFocusedWindowNumber() -> UInt32? { focusedWindowNumber() }

    /// A reader with no window server behind it cannot say what holds the focus, and says so.
    public func focusedApplication() -> InsertionDestination? { nil }

    /// A reader that cannot see the field cannot tell it is secure, and says it is not.
    public func focusedFieldIsSecure() -> Bool { false }

    /// A reader that cannot tell one field from another cannot place a write.
    public func focusedFieldPlace() -> FieldPlace? { nil }

    /// A reader that cannot tell one field from another cannot refuse a write for being in another.
    public func focusedFieldIdentity() -> FieldIdentity? { nil }

    /// A reader with no process-wide trust flag behind it cannot be refused by one.
    public func isTrusted() -> Bool { true }
}
