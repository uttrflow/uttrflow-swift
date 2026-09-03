/// Matches a short abbreviation against a candidate as a subsequence, the way a quick-open box does.
public enum Abbreviation {
    /// The longest query worth abbreviating, past which the user has typed enough for the other matchers.
    public static let maximumQueryLength = 5

    /// Whether this query is short and unbroken enough for a last-resort subsequence match.
    public static func shouldAttempt(query: String) -> Bool {
        guard !query.isEmpty, query.count <= maximumQueryLength else { return false }
        return !query.contains(where: \.isWhitespace)
    }

    /// How well the query abbreviates the candidate, or nil when it is not a subsequence of it.
    public static func score(query: String, candidate: String) -> Double? {
        let needles = Array(query).map { $0.lowercased() }
        let characters = Array(candidate)
        let folded = characters.map { $0.lowercased() }
        guard let first = needles.first, characters.count >= needles.count else { return nil }

        // Best score for a match of the query's opening that ends on each candidate position.
        var endings = [Int?](repeating: nil, count: characters.count)
        for column in folded.indices where folded[column] == first {
            let opening = column == 0 ? startBonus : -gapPenalty(column)
            endings[column] = matchScore + bonus(at: column, in: characters) + opening
        }

        for row in needles.indices.dropFirst() {
            var next = [Int?](repeating: nil, count: characters.count)
            for column in row..<characters.count where folded[column] == needles[row] {
                guard let carried = bestCarried(into: column, from: endings) else { continue }
                next[column] = carried + matchScore + bonus(at: column, in: characters)
            }
            endings = next
        }

        guard let best = endings.compactMap({ $0 }).max() else { return nil }
        return Double(best)
    }

    /// What a matched character is worth before any position is taken into account.
    private static let matchScore = 16

    /// What a match directly after the previous one is worth, which is what favours unbroken runs.
    private static let consecutiveBonus = 10

    /// What a match at the start of a word is worth, which is how an abbreviation is normally read.
    private static let boundaryBonus = 8

    /// What a match on a camelCase hump is worth, a word boundary that has no separator in front of it.
    private static let camelBonus = 7

    /// What matching the candidate's very first character is worth, on top of it being a boundary.
    private static let startBonus = 12

    /// What the first skipped character costs, so scattered matches fall behind unbroken ones.
    private static let gapStart = 3

    /// What each further skipped character costs.
    private static let gapExtension = 1

    /// The most a single gap can cost, so one long stretch cannot sink an otherwise good match.
    private static let maximumGapPenalty = 12

    /// The characters a new word begins after.
    private static let separators: Set<Character> = ["-", "_", "/"]

    /// What skipping this many characters costs, growing with the gap and then flattening.
    private static func gapPenalty(_ length: Int) -> Int {
        min(gapStart + (length - 1) * gapExtension, maximumGapPenalty)
    }

    /// What this position is worth for standing where a reader would look for an abbreviated letter.
    private static func bonus(at index: Int, in characters: [Character]) -> Int {
        guard index > 0 else { return boundaryBonus }
        let previous = characters[index - 1]
        if previous.isWhitespace || separators.contains(previous) { return boundaryBonus }
        if characters[index].isUppercase, previous.isLowercase { return camelBonus }
        return 0
    }

    /// The best score any earlier match can hand to this position, gap and consecutive runs priced in.
    private static func bestCarried(into column: Int, from endings: [Int?]) -> Int? {
        var best: Int?
        for previous in 0..<column {
            guard let carried = endings[previous] else { continue }
            let gap = column - previous - 1
            let value = carried + (gap == 0 ? consecutiveBonus : -gapPenalty(gap))
            best = max(best ?? value, value)
        }
        return best
    }
}
