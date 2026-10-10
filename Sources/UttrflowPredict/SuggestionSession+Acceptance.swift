public import Foundation
public import UttrflowCore

/// Whether insertion succeeded, was refused before writing, or may have written text.
package enum AcceptanceOutcome: Sendable, Equatable {
    /// The insertion was applied to the field.
    case inserted
    /// The field rejected the insertion, so the swallowed key is returned.
    case refused
    /// The insertion may have written text, so the speculative acceptance stays in place.
    case mayHaveWritten

    /// The state an accepted suggestion changed before the field confirmed its insertion.
    struct FailedAcceptanceRollback: Sendable, Equatable {
        let acceptanceGeneration: Int
        let keystrokes: Int
        let acceptedAt: Date
        let suggestion: Suggestion
        let selection: SuggestionSelection
        let surface: Surface?
        let typed: String
        let taken: TakenLine?
        let undoneHere: Set<String>
        let undoMarkGenerations: [String: Int]
        let shownIsGenerated: Bool
        let acceptedText: String
    }
}

extension SuggestionSession {
    /// Takes one keystroke the tap swallowed and answers with what it means.
    public mutating func route(_ stroke: KeyStroke, at now: Date = Date()) -> SuggestionAction {
        switch KeyRouting.decision(
            for: stroke, showing: suggestion, selection: selection, acceptKey: acceptKey)
        {
        case .accept(let text):
            // A key typed since the read this offer was worked out for has moved the line, so Tab takes nothing.
            guard drawnAtKeystroke == keystrokes else { return .giveBack(stroke) }
            let acceptanceGeneration = generation + 1
            failedAcceptance = AcceptanceOutcome.FailedAcceptanceRollback(
                acceptanceGeneration: acceptanceGeneration, keystrokes: keystrokes, acceptedAt: now,
                suggestion: suggestion,
                selection: selection, surface: surface, typed: typed, taken: taken,
                undoneHere: undoneHere, undoMarkGenerations: undoMarkGenerations,
                shownIsGenerated: shownIsGenerated, acceptedText: text)
            // The offer is gone the moment it is taken, and so is any answer still in flight for it.
            generation += 1
            clearDrawing()
            taken = TakenLine(
                line: text, over: typed, moment: now,
                acceptanceGeneration: acceptanceGeneration)
            typed = text
            return .accept(text)
        case .moveSelection(let moved):
            selection = moved
            return .redraw(armed(showing: suggestion, silence: nil))
        case .dismiss(let dismissal):
            return .redraw(dismiss(dismissal))
        case .passThrough:
            return .giveBack(stroke)
        }
    }

    /// Commits the accept state after insertion or restores it if insertion failed without newer field activity.
    package mutating func completeAcceptance(_ outcome: AcceptanceOutcome) {
        guard let rollback = failedAcceptance else { return }
        failedAcceptance = nil
        guard outcome == .refused else { return }
        guard surface == rollback.surface else { return }
        let acceptedKey = TextMatching.caseFoldedKey(rollback.acceptedText)
        if !rollback.undoneHere.contains(acceptedKey),
            undoMarkGenerations[acceptedKey] == rollback.acceptanceGeneration
        {
            undoneHere.remove(acceptedKey)
            undoMarkGenerations.removeValue(forKey: acceptedKey)
        }
        let unchangedField = keystrokes == rollback.keystrokes
        guard unchangedField else { return }
        if let currentTake = taken, currentTake.moment == rollback.acceptedAt,
            currentTake.line == rollback.acceptedText
        {
            taken = rollback.taken
        }
        let noInterveningTurn =
            generation == rollback.acceptanceGeneration
            && typed == rollback.acceptedText
        guard unchangedField && noInterveningTurn else { return }
        suggestion = rollback.suggestion
        selection = rollback.selection
        typed = rollback.typed
        undoneHere = rollback.undoneHere
        undoMarkGenerations = rollback.undoMarkGenerations
        shownIsGenerated = rollback.shownIsGenerated
    }
}
