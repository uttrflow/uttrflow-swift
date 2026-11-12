import CoreGraphics
import UttrflowContext
import UttrflowCore
import UttrflowPredict

extension SuggestionRequest {
    /// The inline ghost at the caret in the field's own face and accept keys, or nil where it has no place.
    static func ghost(
        _ suggestion: Suggestion, typed: String, selection: SuggestionSelection,
        in snapshot: FocusedFieldSnapshot,
        preferences: SuggestionPreferences
    ) -> SuggestionRequest? {
        guard let caret = caret(for: suggestion, in: snapshot) else { return nil }
        return SuggestionRequest(
            suggestion: suggestion.trimmed(after: typed, matching: snapshot.closingPunctuationAfterCaret),
            typed: typed, placement: .inlineGhost,
            direction: snapshot.writingDirection == .rightToLeft ? .rightToLeft : .leftToRight,
            caret: caret, window: snapshot.window, field: snapshot.ghostField,
            fieldPointSize: snapshot.pointSize,
            selection: selection,
            acceptKey: acceptKey(in: snapshot, preferences: preferences),
            wordAcceptKey: preferences.wordAcceptKey(forBundleIdentifier: snapshot.bundleIdentifier),
            fontFamily: snapshot.fontFamily, isBold: snapshot.isBold, isItalic: snapshot.isItalic,
            textColor: snapshot.textColor)
    }

    /// The key that accepts in the field's app, read with its window title so a browser tab counts as its site.
    static func acceptKey(in snapshot: FocusedFieldSnapshot, preferences: SuggestionPreferences) -> AcceptKey
    {
        preferences.acceptKeys.key(
            for: AppContext(
                applicationName: snapshot.applicationName, bundleIdentifier: snapshot.bundleIdentifier,
                documentName: snapshot.windowTitle))
    }

    /// The caret a ghost for `suggestion` is drawn at, or nil when the field offers no inline place for one.
    static func caret(for suggestion: Suggestion, in snapshot: FocusedFieldSnapshot) -> CGRect? {
        guard suggestion != .silent, snapshot.placement == .inlineGhost else { return nil }
        return snapshot.caret
    }
}
