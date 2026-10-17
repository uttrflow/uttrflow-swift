public import UttrflowCore

/// Removes the doubled function word a false start leaves behind: "the the deployment".
public struct StammersPass: PieceCleaningPass {
    public static let id: PassID = .stammers
    public static let laws: Set<PassLaw> = [.idempotent, .addsNoWords, .latinOnly]
    public static let orderIndependentWith: Set<PassID> = [.selfCorrection]
    public static let removes: RemovalGrant = .repetition

    /// Function words English doubles on purpose: a past perfect, a doubled relative, a conjunction, a comforting.
    static let legitimateDoubles: Set<String> = ["had", "that", "so", "there"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        // The three arrays shrink together with each removal, so every test reads the words a second run would read.
        var live = draft.presentIndices
        var shapes = live.map { draft.shape(at: $0) }
        var keys = shapes.map(\.key)
        var previous: String?
        var i = 0
        while i < live.count {
            let index = live[i]
            let word = draft.words[index].text.lowercased()
            if word == previous, Self.preservesHindiDistributiveDo(at: i, in: live, draft: draft) {
                previous = word
                i += 1
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
                live.remove(at: i)
                shapes.remove(at: i)
                keys.remove(at: i)
                continue
            }
            // A doubled number is data unless it is a single-word cardinal stammered at the start of a piece.
            if word == previous, Self.isSingleWordCardinal(word),
                Self.isStammerPosition(at: i, in: live),
                !Self.surroundedByNumber(at: i, in: live, draft: draft),
                !NumberFormsPass.hasLabelCue(at: i - 1, keys: keys, shapes: shapes)
            {
                draft.remove(at: index, by: Self.id, carryingMarks: true)
                live.remove(at: i)
                shapes.remove(at: i)
                keys.remove(at: i)
                continue
            }
            previous = word
            i += 1
        }
        return draft
    }

    /// Whether the number is one word from zero to nineteen; a tens or scale word doubles as a year, a score or an even split.
    private static func isSingleWordCardinal(_ word: String) -> Bool {
        NumberWords.units[word] != nil || NumberWords.teens[word] != nil
    }

    /// Whether the pair opens the piece and a word follows it, the only place a doubled number reads as a restart.
    private static func isStammerPosition(at i: Int, in live: [Int]) -> Bool {
        i == 1 && live.count > 2
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
