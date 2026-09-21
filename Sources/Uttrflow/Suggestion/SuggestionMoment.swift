import Foundation
import UttrflowContext
import UttrflowPredict
import UttrflowPredictCapture

/// What one reading of the focused field becomes for the capture store, the quieting rules and the model.
enum SuggestionMoment {
    /// How much of the text before the caret's line the model is shown, enough for the sentence or command before it.
    static let precedingContextLength = 400
    /// How many of this person's recent lines in the field the model is shown, enough to hear their voice in it.
    static let recentLinesShown = 6

    /// What the field publishes about itself, in the shape the corpus keys entries by.
    static func reading(of snapshot: FocusedFieldSnapshot) -> FieldReading {
        FieldReading(
            bundleIdentifier: snapshot.bundleIdentifier, role: snapshot.role,
            subrole: snapshot.subrole, identifier: snapshot.identifier,
            placeholder: snapshot.placeholder,
            accessibilityDescription: snapshot.accessibilityDescription, document: snapshot.document,
            windowTitle: snapshot.windowTitle, applicationName: snapshot.applicationName)
    }

    /// Everything about this moment that can silence a suggestion, given how long since the last keystroke.
    static func context(
        of snapshot: FocusedFieldSnapshot, millisecondsSinceKeystroke: Int
    ) -> PredictionContext {
        PredictionContext(
            typed: snapshot.currentLine, caretAtLineEnd: snapshot.caretAtLineEnd,
            hasSelection: snapshot.hasSelection, isComposing: snapshot.isComposing,
            isSecure: snapshot.isSecure, isProse: snapshot.isProse,
            millisecondsSinceKeystroke: millisecondsSinceKeystroke,
            canDraw: snapshot.placement == .inlineGhost, markedText: snapshot.markedText)
    }

    /// Which window a walk belongs to, from what the field read already says about it.
    static func windowKey(of snapshot: FocusedFieldSnapshot) -> String {
        "\(snapshot.bundleIdentifier)\u{1F}\(snapshot.document ?? "")"
    }

    /// The remembered lines worth showing, less any the line being written already begins with.
    static func recentLines(_ remembered: [String], typing typed: String) -> [String] {
        // The line being written is not a line written before, however long the pause that had it remembered.
        remembered.filter { !typed.hasPrefix($0) }
    }

    /// Everything the model is told about the moment: the field, what is on screen around it, and how this person writes here.
    static func situation(
        of snapshot: FocusedFieldSnapshot, surroundings around: Surroundings?, recentLines recent: [String]
    ) -> GenerationSituation {
        GenerationSituation(
            application: snapshot.applicationName,
            field: snapshot.accessibilityDescription ?? snapshot.placeholder ?? snapshot.role,
            document: snapshot.document,
            preceding: snapshot.preceding(maxLength: precedingContextLength),
            windowTitle: around?.windowTitle, surroundings: around?.text, recentLines: recent,
            isMultiline: snapshot.role == FocusedFieldSnapshot.proseRole
                || snapshot.value?.contains(where: \.isNewline) == true)
    }
}
