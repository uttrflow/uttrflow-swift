import func Foundation.exp

/// How likely somebody meaning one word was to have typed another, which is the noisy channel's P(typed | meant).
public enum TypoModel {
    /// What swapping two neighbouring characters costs, being the commonest slip a keyboard produces.
    public static let transpositionCost = 1.1

    /// What doubling a letter, or dropping one of a doubled pair, costs.
    public static let repeatedLetterCost = 1.3

    /// What hitting a key physically next to the intended one costs.
    public static let adjacentSubstitutionCost = 1.8

    /// What typing a stray character, or missing one out, costs.
    public static let indelCost = 3.2

    /// What hitting a key nowhere near the intended one costs.
    public static let distantSubstitutionCost = 4.0

    /// How much dearer the same slip is in the first character, which people rarely get wrong.
    public static let firstCharacterMultiplier = 2.4

    /// How likely the typed text was given what was meant, 1 when they are the same and never 0 below it.
    public static func likelihood(typed: String, meant: String) -> Double {
        exp(logLikelihood(typed: typed, meant: meant))
    }

    /// The same likelihood in logs, where costs add rather than multiply and nothing underflows.
    public static func logLikelihood(typed: String, meant: String) -> Double {
        -cost(typed: Array(typed.lowercased()), meant: Array(meant.lowercased()))
    }

    /// The cheapest sequence of slips that turns what was meant into what was typed.
    static func cost(typed: [Character], meant: [Character]) -> Double {
        var table = [[Double]](
            repeating: [Double](repeating: 0, count: typed.count + 1), count: meant.count + 1)
        for i in 1..<(meant.count + 1) {
            table[i][0] = table[i - 1][0] + deletion(meant, at: i)
        }
        for j in 1..<(typed.count + 1) {
            table[0][j] = table[0][j - 1] + insertion(typed, at: j)
        }
        for i in 1..<(meant.count + 1) {
            for j in 1..<(typed.count + 1) {
                table[i][j] = step(table, typed: typed, meant: meant, i: i, j: j)
            }
        }
        return table[meant.count][typed.count]
    }

    /// The cheapest way to reach one cell, weighing substitution, both indels and a transposition.
    private static func step(
        _ table: [[Double]], typed: [Character], meant: [Character], i: Int, j: Int
    ) -> Double {
        let same = meant[i - 1] == typed[j - 1]
        let substituted =
            table[i - 1][j - 1] + (same ? 0 : substitution(meant[i - 1], typed[j - 1], atStart: i == 1))
        var best = min(substituted, table[i - 1][j] + deletion(meant, at: i))
        best = min(best, table[i][j - 1] + insertion(typed, at: j))
        guard i > 1, j > 1, meant[i - 1] == typed[j - 2], meant[i - 2] == typed[j - 1] else { return best }
        return min(best, table[i - 2][j - 2] + weighted(transpositionCost, atStart: i == 2))
    }

    /// What it costs to have hit one key while meaning another, by how far apart they sit.
    static func substitution(_ meant: Character, _ typed: Character, atStart: Bool) -> Double {
        weighted(
            areAdjacent(meant, typed) ? adjacentSubstitutionCost : distantSubstitutionCost, atStart: atStart)
    }

    /// What it costs to have missed out the meant character in that position, cheaply when it was a repeat.
    static func deletion(_ meant: [Character], at i: Int) -> Double {
        let repeats = (i > 1 && meant[i - 1] == meant[i - 2]) || (i < meant.count && meant[i - 1] == meant[i])
        return weighted(repeats ? repeatedLetterCost : indelCost, atStart: i == 1)
    }

    /// What it costs to have typed an extra character in that position, cheaply when it doubled a neighbour.
    static func insertion(_ typed: [Character], at j: Int) -> Double {
        let repeats = (j > 1 && typed[j - 1] == typed[j - 2]) || (j < typed.count && typed[j - 1] == typed[j])
        return weighted(repeats ? repeatedLetterCost : indelCost, atStart: j == 1)
    }

    /// The same slip, dearer when it lands on the first character.
    static func weighted(_ cost: Double, atStart: Bool) -> Double {
        atStart ? cost * firstCharacterMultiplier : cost
    }

    /// Whether two keys touch on the keyboard, false for anything the table does not carry.
    static func areAdjacent(_ one: Character, _ other: Character) -> Bool {
        neighbours[one]?.contains(other) ?? false
    }

    /// Which letter keys touch which on a QWERTY keyboard, counting the staggered rows above and below.
    static let neighbours: [Character: Set<Character>] = [
        "q": ["w", "a", "s"],
        "w": ["q", "e", "a", "s", "d"],
        "e": ["w", "r", "s", "d", "f"],
        "r": ["e", "t", "d", "f", "g"],
        "t": ["r", "y", "f", "g", "h"],
        "y": ["t", "u", "g", "h", "j"],
        "u": ["y", "i", "h", "j", "k"],
        "i": ["u", "o", "j", "k", "l"],
        "o": ["i", "p", "k", "l"],
        "p": ["o", "l"],
        "a": ["q", "w", "s", "z"],
        "s": ["q", "w", "e", "a", "d", "z", "x"],
        "d": ["w", "e", "r", "s", "f", "x", "c"],
        "f": ["e", "r", "t", "d", "g", "c", "v"],
        "g": ["r", "t", "y", "f", "h", "v", "b"],
        "h": ["t", "y", "u", "g", "j", "b", "n"],
        "j": ["y", "u", "i", "h", "k", "n", "m"],
        "k": ["u", "i", "o", "j", "l", "m"],
        "l": ["i", "o", "p", "k"],
        "z": ["a", "s", "x"],
        "x": ["z", "s", "d", "c"],
        "c": ["x", "d", "f", "v"],
        "v": ["c", "f", "g", "b"],
        "b": ["v", "g", "h", "n"],
        "n": ["b", "h", "j", "m"],
        "m": ["n", "j", "k"],
    ]
}
