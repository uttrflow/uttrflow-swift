/// What the focused field says about an input method's marked text, which only some fields answer.
public enum MarkedText: Sendable, Equatable, CaseIterable {
    /// The field reports marked text, so an input method is mid-composition in it.
    case present
    /// The field reports no marked text, which settles the question on its own.
    case absent
    /// The field does not publish a marked range, so it has said nothing either way.
    case unanswered
}

/// What kind of keyboard input source is selected, which says whether composing is possible at all.
public enum InputSourceKind: Sendable, Equatable, CaseIterable {
    /// A static key map, which turns a keystroke into a character and never composes.
    case layout
    /// An input method, which may hold marked text between the keystroke and the character.
    case inputMethod
    /// The input source could not be read, which rules nothing out.
    case unknown

    /// Whether a source of this kind can hold marked text, which only a plain layout cannot.
    public var mayCompose: Bool { self != .layout }
}

/// Decides whether an input method may be mid-composition. See `Docs/predict-ime.md`.
public enum Composition {
    /// Whether to treat this moment as composing, trusting the field over the input source.
    public static func isComposing(markedText: MarkedText, inputSource: InputSourceKind) -> Bool {
        switch markedText {
        case .present: true
        case .absent: false
        case .unanswered: inputSource.mayCompose
        }
    }
}
