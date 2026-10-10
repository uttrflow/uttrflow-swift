import Foundation
import UttrflowContext
import UttrflowCore
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
            accessibilityDescription: snapshot.accessibilityDescription, title: snapshot.title,
            document: snapshot.document,
            windowTitle: snapshot.windowTitle, windowNumber: snapshot.windowNumber,
            applicationName: snapshot.applicationName,
            isKnownSecure: snapshot.isSecure)
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
            canDraw: snapshot.placement == .inlineGhost, markedText: snapshot.markedText,
            isCommandLine: TerminalApplications.contains(snapshot.bundleIdentifier),
            showsOwnList: snapshot.showsOwnList,
            writingDirectionKnown: snapshot.writingDirection != .unknown)
    }

    /// Where in the field the line sits: the text before it, exactly as much as the model is shown.
    static func place(of snapshot: FocusedFieldSnapshot) -> String? {
        snapshot.preceding(maxLength: precedingContextLength)
    }

    /// Which window a walk belongs to, from what the field read already says about it.
    static func windowKey(of snapshot: FocusedFieldSnapshot) -> String {
        let parts: [String?] = [
            snapshot.bundleIdentifier, snapshot.document, snapshot.windowTitle,
            snapshot.windowNumber.map { String($0) },
        ]
        return parts.map { part in
            guard let part else { return "-" }
            return "\(part.utf8.count):\(part)"
        }
        .joined(separator: "\u{1F}")
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
        let isTerminal = TerminalApplications.contains(snapshot.bundleIdentifier)
        let destination = DestinationClassifier.classify(
            AppContext(
                applicationName: snapshot.applicationName, bundleIdentifier: snapshot.bundleIdentifier,
                documentName: snapshot.windowTitle ?? snapshot.document))
        let isCodeDestination = ["sqlEditor", "codeEditor"].contains(destination.rawValue)
        var situation = GenerationSituation(
            application: snapshot.applicationName,
            isCodeDestination: isCodeDestination,
            field: snapshot.fieldLabel ?? snapshot.role,
            document: snapshot.document,
            preceding: snapshot.preceding(maxLength: precedingContextLength),
            windowTitle: around?.windowTitle, surroundings: around?.text, recentLines: recent,
            timedTurnLines: around?.timedTurnLines ?? 0,
            isMultiline: !isTerminal
                && (snapshot.role == FocusedFieldSnapshot.proseRole
                    || snapshot.value?.contains(where: \.isNewline) == true)
        )
        situation.accessibilityRole = snapshot.role
        situation.isCommandLine = isTerminal
        return situation
    }
}
