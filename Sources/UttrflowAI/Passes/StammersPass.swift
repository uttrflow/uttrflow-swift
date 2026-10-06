public import UttrflowCore

/// Removes the doubled function word a false start leaves behind: "the the deployment".
public struct StammersPass: PieceCleaningPass {
    public static let id: PassID = .stammers
    public static let removes: RemovalGrant = .repetition

    /// Function words English doubles on purpose: a past perfect, a doubled relative, a conjunction, a comforting.
    static let legitimateDoubles: Set<String> = ["had", "that", "so", "there"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        var previous: String?
        for (i, index) in live.enumerated() {
            let word = draft.words[index].text.lowercased()
            if word == previous, Self.preservesHindiDistributiveDo(at: i, in: live, draft: draft) {
                previous = word
                continue
            }
            if word == previous, !draft.isHindi(at: index),
                (!FunctionWords.isContent(word) || MeaningPreservationGuard.isGrammarWord(word)),
                !Self.legitimateDoubles.contains(word),
                // A doubled negation is emphasis, and dropping a negation is the worst edit there is.
                !MeaningPreservationGuard.isNegation(word),
                // A doubled letter name in a spelled run is data, not a stammer.
                !SpelledInitialismPass.isSpelledRun(around: i, in: live, draft: draft)
            {
                // A doubled function word is a stammer.
                draft.remove(at: index, by: Self.id, carryingMarks: true)
                continue
            }
            // A doubled number is a digit of one value when another number sits beside the pair, otherwise a stammer.
            if word == previous, NumberWords.isNumber(word),
                !Self.isDoubledNumberAtPieceEdge(at: i, in: live),
                !Self.surroundedByNumber(at: i, in: live, draft: draft)
            {
                draft.remove(at: index, by: Self.id, carryingMarks: true)
                continue
            }
            previous = word
        }
        return draft
    }

    /// Keeps an ambiguous doubled digit when its pair touches a piece boundary.
    private static func isDoubledNumberAtPieceEdge(at i: Int, in live: [Int]) -> Bool {
        i == 1 || i == live.count - 1
    }

    /// Keeps Hindi's doubled numeral when a content word follows it.
    private static func preservesHindiDistributiveDo(at i: Int, in live: [Int], draft: Draft) -> Bool {
        guard i > 0, i + 1 < live.count,
            draft.words[live[i - 1]].text.lowercased() == "do"
        else { return false }
        return FunctionWords.isContent(draft.words[live[i + 1]].text.lowercased())
    }

    /// Whether a number word sits immediately before or after the doubled pair at `i`, read by key so a closing mark does not hide it.
    private static func surroundedByNumber(at i: Int, in live: [Int], draft: Draft) -> Bool {
        if i >= 2 {
            let prev = draft.shape(at: live[i - 2]).key
            if NumberWords.isNumber(prev) || prev == "point" { return true }
        }
        return i + 1 < live.count && NumberWords.isNumber(draft.shape(at: live[i + 1]).key)
    }
}
