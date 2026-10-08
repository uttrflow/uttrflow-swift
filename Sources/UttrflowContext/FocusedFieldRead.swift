import Foundation
import UttrflowCore
import UttrflowPredict

/// The focused field's names and bounded value, decided over any `ElementTree` so every refusal is testable.
enum FocusedFieldRead {
    /// The names the secure check and the field label read, in the order a batched read answers them.
    static let nameAttributes = [
        "AXRole", "AXSubrole", "AXIdentifier", "AXPlaceholderValue", "AXDescription", "AXTitle",
    ]

    /// The field's names, asked in one message where the tree batches them.
    static func names<Tree: ElementTree>(of field: Tree.Element, in tree: Tree) -> FieldNames {
        let answers = tree.attributes(nameAttributes, of: field)
        guard answers.count == nameAttributes.count else {
            return FieldNames(
                role: nil, subrole: nil, identifier: nil, placeholder: nil, description: nil,
                readStatus: .refused)
        }
        let named = answers.map(\.string)
        let refused = answers.contains { answer in
            switch answer {
            case .cannotComplete, .timedOut: true
            case .value, .noValue, .unsupported: false
            }
        }
        return FieldNames(
            role: named[0], subrole: named[1], identifier: named[2], placeholder: named[3],
            description: named[4], title: named[5],
            readStatus: refused || named[0] == nil ? .refused : .complete)
    }

    /// The field's text around the caret with the selection moved into it, after the names clear the secure check.
    static func text<Tree: ElementTree>(
        of field: Tree.Element, in tree: Tree, names: FieldNames, at selection: NSRange?,
        need: ContextNeed = .turn,
        count: (() -> Int?)? = nil
    ) -> FieldText {
        guard !names.isSecureOrUnknown else {
            return FieldText(value: nil, selection: nil, isSecure: true, rung: .none)
        }
        // A caller that already holds the length from a batched read passes it, so it is not asked twice.
        let askCount = count ?? { tree.attribute("AXNumberOfCharacters", of: field).integer }
        let count = selection == nil ? nil : askCount()
        let read = ValueWindow.read(
            count: count, selection: selection, need: need,
            whole: { tree.attribute("AXValue", of: field).string },
            part: { tree.attribute("AXStringForRange", of: field, range: $0).string })
        return FieldText(
            value: read.value, selection: read.selection, isSecure: names.isSecure(value: { read.value }),
            rung: read.rung)
    }
}

extension FocusedFieldRead {
    /// UTF-16 units of a selection asked for: one character past the kept limit at four units each, so a cut is seen.
    static let selectionReadUnits = (MacContextEngine.selectedTextLimit + 1) * 4

    /// The selection's opening stretch by a ranged read, or `nil` when the field refuses it, never the whole selection.
    static func selectedText<Tree: ElementTree>(
        of field: Tree.Element, in tree: Tree, at selection: NSRange?
    ) -> String? {
        guard let selection, selection.location >= 0, selection.length > 0 else { return nil }
        let window = NSRange(location: selection.location, length: min(selection.length, selectionReadUnits))
        return tree.attribute("AXStringForRange", of: field, range: window).string
    }
}

extension FocusedFieldRead {
    /// The range an input method is composing into, which AppKit text views publish and little else does.
    static let markedRangeAttribute = "AXTextInputMarkedRange"

    /// The field's selection, refusing to guess at a multi-range caret, each attribute one message.
    static func selection<Tree: ElementTree>(
        of field: Tree.Element, in tree: Tree, decode: FieldAnswerDecoder<Tree.Element>
    ) -> AccessibilitySelection {
        let plural = tree.attribute("AXSelectedTextRanges", of: field).object as? [Any]
        if let plural, plural.count > 1 { return .discontinuous }
        let singular = tree.attribute("AXSelectedTextRange", of: field).object.flatMap(decode.range)
        return AccessibilitySelection.resolve(
            singular: singular, plural: plural?.compactMap(decode.range),
            textLength: tree.attribute("AXNumberOfCharacters", of: field).integer)
    }

    /// What the field says about its marked text, an unanswered read being no evidence either way.
    static func markedText<Tree: ElementTree>(
        of field: Tree.Element, in tree: Tree, decode: FieldAnswerDecoder<Tree.Element>
    ) -> MarkedText {
        guard let range = tree.attribute(markedRangeAttribute, of: field).object.flatMap(decode.range) else {
            return .unanswered
        }
        return range.length > 0 ? .present : .absent
    }
}

/// The focused field's text around the caret, with the selection moved into it, and whether the field is secure.
struct FieldText {
    let value: String?
    let selection: NSRange?
    let isSecure: Bool
    /// Which rung of the read ladder gives the value.
    let rung: ContextReadRung
}
