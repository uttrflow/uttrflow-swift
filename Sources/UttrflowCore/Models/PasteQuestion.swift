/// Decides whether a paste goes in at once or waits for the user, so every confirm-before-paste question has one source.
public enum PasteQuestion {
    /// The kind of field a hidden clip is headed for.
    public enum Field: Sendable, Equatable {
        /// A field that hides what is typed.
        case secure
        /// A field that shows what is typed.
        case nonSecure
        /// No focused field could be read.
        case unclassified
    }

    /// Why the user is asked, which words the question.
    public enum Reason: Sendable, Equatable {
        /// A hidden clip is headed for a field that shows what is pasted.
        case hiddenIntoVisibleField
        /// A hidden clip is headed for a field that could not be read.
        case hiddenIntoUnreadableField
        /// A terminal would run each line of the clip as it arrives; `lines` is 1 when only a trailing break does.
        case multilineIntoTerminal(lines: Int)

        /// Whether the question is about a hidden clip, which must still be hidden when the user agrees.
        public var isAboutHiddenClip: Bool {
            if case .multilineIntoTerminal = self { return false }
            return true
        }

        /// The question's title, never carrying the clip's words.
        public var title: String {
            switch self {
            case .hiddenIntoVisibleField: "Paste a hidden clip into a text field?"
            case .hiddenIntoUnreadableField: "Paste a hidden clip here?"
            case .multilineIntoTerminal(let lines):
                lines > 1
                    ? "This clip has \(lines) lines. Paste anyway?"
                    : "This clip ends with a new line. Paste anyway?"
            }
        }

        /// The line under the title.
        public var note: String {
            switch self {
            case .hiddenIntoVisibleField: "This field shows what is pasted. Return pastes, Esc cancels."
            case .hiddenIntoUnreadableField:
                "This field cannot be checked, so it may show what is pasted. Return pastes, Esc cancels."
            case .multilineIntoTerminal:
                "A new line in a terminal runs the line before it. Return pastes, Esc cancels."
            }
        }
    }

    /// Why a paste the user agreed to is not made.
    public enum Refusal: Sendable, Equatable {
        /// The cursor is in another field than the one the question named.
        case fieldMoved

        /// What to tell the user.
        public var message: String { "Not pasted — the cursor moved to another field" }
    }

    /// What to do with the paste.
    public enum Decision: Sendable, Equatable {
        /// Paste without asking.
        case pasteNow
        /// Ask first, for this reason.
        case ask(Reason)
        /// Do not paste.
        case refuse(Refusal)
    }

    /// What is known about one paste.
    public struct Situation: Sendable, Equatable {
        /// Whether the clip is hidden on screen.
        public var isConcealed: Bool
        /// What the destination field is; read only for a hidden clip.
        public var field: Field
        /// The destination application's bundle identifier.
        public var bundleIdentifier: String?
        /// The clip text as it would be pasted.
        public var text: String
        /// Whether to ask before a hidden clip goes into a field not known to hide it.
        public var confirmsHiddenClips: Bool
        /// Whether to ask before a clip with a line break goes into a terminal.
        public var confirmsMultiline: Bool

        /// Whether the user already answered the question for this paste.
        public var isAgreed: Bool
        /// For an agreed paste, whether the focus is still on the field the question named.
        public var fieldUnchanged: Bool

        /// Gathers what the decision reads.
        public init(
            isConcealed: Bool, field: Field, bundleIdentifier: String?, text: String,
            confirmsHiddenClips: Bool, confirmsMultiline: Bool, isAgreed: Bool = false,
            fieldUnchanged: Bool = true
        ) {
            self.isAgreed = isAgreed
            self.fieldUnchanged = fieldUnchanged
            self.isConcealed = isConcealed
            self.field = field
            self.bundleIdentifier = bundleIdentifier
            self.text = text
            self.confirmsHiddenClips = confirmsHiddenClips
            self.confirmsMultiline = confirmsMultiline
        }

        /// Whether the destination field must be read before deciding.
        public var needsFieldRead: Bool { isConcealed && confirmsHiddenClips && !isAgreed }
    }

    /// Decides the paste; a hidden clip's question comes before a terminal's so one paste asks once.
    public static func decide(_ situation: Situation) -> Decision {
        if situation.isAgreed { return situation.fieldUnchanged ? .pasteNow : .refuse(.fieldMoved) }
        if situation.needsFieldRead {
            switch situation.field {
            case .secure: break
            case .nonSecure: return .ask(.hiddenIntoVisibleField)
            case .unclassified: return .ask(.hiddenIntoUnreadableField)
            }
        }
        guard situation.confirmsMultiline, hasLineBreak(situation.text),
            let bundleIdentifier = situation.bundleIdentifier,
            TerminalApplications.contains(bundleIdentifier)
        else { return .pasteNow }
        return .ask(.multilineIntoTerminal(lines: lineCount(of: situation.text)))
    }

    /// How many lines the clip holds, with a trailing line break ending the last line rather than starting another.
    public static func lineCount(of text: String) -> Int {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return text.last?.isNewline == true ? lines.count - 1 : lines.count
    }

    /// Whether the clip has a line break in its middle or at its end.
    public static func hasLineBreak(_ text: String) -> Bool {
        text.contains(where: \.isNewline)
    }
}
