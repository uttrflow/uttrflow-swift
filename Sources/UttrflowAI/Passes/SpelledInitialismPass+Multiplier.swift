import UttrflowCore

/// Writes a lone spoken "x" after a number as a multiplier joined to it: "ten x faster" is "10x faster".
extension SpelledInitialismPass {
    /// The words that, after "x", show it is a multiplier and not a letter, a dimension or a name.
    private static let comparisons = FunctionWords.multiplierComparisons

    /// The draft with each number then multiplier "x" written as one token.
    static func writingMultipliers(in draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        for position in live.indices.dropFirst() {
            let number = draft.shape(at: live[position - 1])
            let letter = draft.shape(at: live[position])
            guard letter.prefix.isEmpty, letter.core == "x",
                joinsNumber(live[position - 1]..<live[position], in: draft),
                number.prefix.isEmpty, number.suffix.isEmpty, isDigits(number.core),
                !draft.words[live[position - 1]].isLayoutMark, !draft.words[live[position]].isLayoutMark,
                !number.endsClause, closesMultiplier(after: position, in: live, draft: draft)
            else { continue }
            write(number.core + "x", over: live[(position - 1)...position], in: &draft)
        }
        return draft
    }

    /// Whether only the words the number pass took in lie between the number and the "x".
    private static func joinsNumber(_ gap: Range<Int>, in draft: Draft) -> Bool {
        draft.words[(gap.lowerBound + 1)..<gap.upperBound].allSatisfy {
            $0.state == .removed(by: NumberFormsPass.id)
        }
    }

    /// Whether the number is plain digits with at most one decimal point.
    private static func isDigits(_ core: String) -> Bool {
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        return (1...2).contains(parts.count)
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// Whether the "x" ends its clause or a comparison follows it directly.
    private static func closesMultiplier(after position: Int, in live: [Int], draft: Draft) -> Bool {
        if draft.shape(at: live[position]).endsClause || position + 1 == live.count { return true }
        return live[position + 1] == live[position] + 1
            && comparisons.contains(draft.shape(at: live[position + 1]).key)
    }
}
