import CoreGraphics
import UttrflowContext
import UttrflowCore
import UttrflowPredict
import UttrflowUX

/// What the surface was last asked to draw, so a display setting can change under it.
struct SuggestionRequest: Equatable {
    var suggestion: Suggestion = .silent
    /// What is already in the field, so the surface offers only what the suggestion adds.
    var typed: String = ""
    var placement: SuggestionPlacement = .inlineGhost
    var direction: WritingDirection = .leftToRight
    var caret: CGRect?
    var window: CGRect?
    /// The field's own rectangle, whose right edge a long ghost is cut at.
    var field: CGRect?
    var fieldPointSize: CGFloat?
    /// Where the arrow keys have put the highlight, and whether they have moved it at all.
    var selection: SuggestionSelection = .untouched
    /// The key that accepts in this field, so the hint drawn after the ghost is the key that works.
    var acceptKey: AcceptKey = .tab
    var wordAcceptKey: WordAcceptKey?
    /// The field's own font family, so the ghost is set in the face the line is.
    var fontFamily: String?
    var isBold = false
    var isItalic = false
    /// The field's own text colour, so the ghost reads against the field and not against Uttrflow's appearance.
    var textColor: TextColor?
    /// The offer the last take-down removed, which a refused accept puts back.
    private(set) var takenDown: Suggestion?

    /// How far apart two reads of one caret may be and still be the same place, since a field can report it a point off.
    static let caretTolerance: CGFloat = 1

    /// Whether this asks for exactly what `other` drew, the caret allowed its read-to-read wobble.
    func draws(sameAs other: Self) -> Bool {
        var aligned = self
        aligned.caret = other.caret
        aligned.takenDown = other.takenDown
        return aligned == other && Self.sameCaret(caret, other.caret)
    }

    /// Takes the offer off the surface, keeping it so a refused accept can put it back.
    mutating func takeDown() {
        if suggestion != .silent { takenDown = suggestion }
        suggestion = .silent
    }

    /// Puts back the offer the last take-down removed, answering whether there was one.
    mutating func putBack() -> Bool {
        guard let takenDown else { return false }
        suggestion = takenDown
        self.takenDown = nil
        return true
    }

    /// Whether two caret reads are one place.
    private static func sameCaret(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.minX - rhs.minX) <= caretTolerance && abs(lhs.maxX - rhs.maxX) <= caretTolerance
            && abs(lhs.minY - rhs.minY) <= caretTolerance && abs(lhs.maxY - rhs.maxY) <= caretTolerance
    }
}
