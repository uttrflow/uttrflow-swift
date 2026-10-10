import UttrflowCore

/// The one rule for when spoken code symbols are written: the screen's cues, then the speech's, against one threshold.
enum NotationEvidence {
    /// The confidence notation needs; one screen cue reaches it and no speech cue alone does. See `Docs/adapters.md` §2.
    static let activationThreshold = 1.0

    /// What the screen says before a word is read: a command line or a caret in code for, a comment or prose body against.
    static func applicability(
        destination: Destination, region: CaretStructure.Region
    ) -> Applicability {
        if destination == .terminal { return Applicability(cues: [.commandLine]) }
        // A query's string literal is a value the speaker words, so it is no more a statement than a comment is.
        if destination == .sqlEditor, region != .code, region != .unrecognised {
            return Applicability(cues: [.caretInProse])
        }
        guard destination == .codeEditor else { return .noEvidence }
        switch region {
        case .code, .string: return Applicability(cues: [.caretInCode])
        case .comment, .prose: return Applicability(cues: [.caretInProse])
        case .unrecognised: return .noEvidence
        }
    }

    /// Whether a notation pass belongs in the pipeline: on the screen's evidence, or in a query editor the screen does not rule out.
    static func mayActivate(_ screen: Applicability, in destination: Destination) -> Bool {
        screen.activates(at: activationThreshold) || (destination == .sqlEditor && screen == .noEvidence)
    }

    /// A query editor's evidence, read from the opening word: a statement opens with a statement keyword, a sentence about one does not.
    static func applicability(
        destination: Destination, opening word: String?, given screen: Applicability
    ) -> Applicability {
        guard destination == .sqlEditor, screen == .noEvidence, let word, statementOpeners.contains(word) else {
            return screen
        }
        return Applicability(cues: [.queryStatement])
    }

    /// The words a dictated statement opens with; the rest of its keywords are rows of the notation table.
    static let statementOpeners: Set<String> = ["select", "insert", "update", "delete"]

    /// The screen's evidence with the speech's cues added: an article, or a determiner before a longer non-notation word ("our costs", not "this dot").
    static func applicability(of words: [String], given screen: Applicability) -> Applicability {
        let readsAsProse = words.indices.contains { index in
            if FunctionWords.prose.contains(words[index]) { return true }
            guard FunctionWords.determiners.contains(words[index]), index + 1 < words.count else {
                return false
            }
            let next = words[index + 1]
            return next.count > 1 && FunctionWords.isContent(next) && !notationWords.contains(next)
        }
        return readsAsProse ? screen.adding([.proseWord]) : screen
    }

    /// A word that, just before a notation word, makes it a noun ("a dot") rather than a command.
    static let nounMarker = "a"

    /// Every word that begins a spoken notation command.
    private static let notationWords: Set<String> = Set(SpokenCommands.codeSymbols.compactMap(\.words.first))
}
