public import UttrflowCore

/// Restores the grouping a model dropped from a numeral the rules had grouped, as the destination's policy wants.
public struct DigitGroupingPass: PieceCleaningPass {
    public static let id: PassID = "digitGrouping"
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    public let digits: DigitGrouping
    /// The piece after its ordinary cleaning passes, before the model rewrites it.
    public let spokenText: String?

    public init(digits: DigitGrouping, spokenText: String? = nil) {
        self.digits = digits
        self.spokenText = spokenText
    }

    public func apply(_ draft: Draft) -> Draft {
        guard digits != .none, let spokenText else { return draft }
        let grouped = Set(
            WordTokens.words(spokenText, .display).map { WordShape($0).core }
                .filter { $0.contains(",") })
        guard !grouped.isEmpty else { return draft }
        var draft = draft
        for index in draft.presentIndices {
            let shape = WordShape(draft.words[index].text)
            guard !shape.core.isEmpty, shape.core.allSatisfy(\.isASCIIDigit), let value = Int(shape.core)
            else { continue }
            // Only a number handed to the model grouped is regrouped, so a year or an id stays as written.
            let rendered = NumberWords.render(value, grouping: digits)
            guard rendered != shape.core, grouped.contains(rendered) else { continue }
            draft.replace(at: index, with: shape.prefix + rendered + shape.suffix, by: Self.id)
        }
        return draft
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
