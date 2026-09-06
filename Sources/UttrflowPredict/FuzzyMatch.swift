/// Matches what the user typed against a candidate when the typing was not quite right.
public enum FuzzyMatch {
    /// The most edits allowed for a query of this length, so a short query cannot match everything.
    public static func budget(forQueryOfLength length: Int) -> Int {
        switch length {
        case ..<3: 0
        case 3...5: 1
        default: 2
        }
    }

    /// The set of characters in a window, as one word, so a candidate can be rejected by popcount.
    public static func mask(_ bytes: some Sequence<UInt8>) -> UInt64 {
        var set: UInt64 = 0
        for byte in bytes {
            let lowered = (byte >= 65 && byte <= 90) ? byte + 32 : byte
            set |= 1 << UInt64(lowered % 63)
        }
        return set
    }

    /// How wide a candidate's mask must be to reject soundly for this query, never narrower.
    public static func maskWidth(forQueryOfLength length: Int, within budget: Int) -> Int {
        length + budget
    }

    /// Whether a candidate could possibly be within budget, cheap and never wrong in the rejecting direction.
    public static func couldMatch(query: UInt64, candidate: UInt64, within budget: Int) -> Bool {
        (query & ~candidate).nonzeroBitCount <= budget
    }

    /// One ASCII byte lowercased, so matching ignores the capital a field puts on the first letter.
    static func folded(_ byte: UInt8) -> UInt8 {
        (byte >= 65 && byte <= 90) ? byte + 32 : byte
    }

    /// Edits from the query to the nearest opening of a candidate, counting a transposition as one, ignoring case.
    public static func prefixDistance(_ query: [UInt8], _ candidate: [UInt8], within budget: Int) -> Int {
        let rows = query.count
        guard rows > 0 else { return 0 }
        let columns = min(candidate.count, rows + budget)
        guard columns > 0 else { return rows }

        let query = query.map(folded)
        let candidate = candidate.map(folded)

        var beforeLast = [Int](repeating: 0, count: columns + 1)
        var last = Array(0...columns)
        var current = [Int](repeating: 0, count: columns + 1)

        for row in 1...rows {
            current[0] = row
            var best = row
            for column in 1...columns {
                let substitution = query[row - 1] == candidate[column - 1] ? 0 : 1
                var cell = min(
                    last[column] + 1, current[column - 1] + 1, last[column - 1] + substitution)
                if row > 1, column > 1, query[row - 1] == candidate[column - 2],
                    query[row - 2] == candidate[column - 1]
                {
                    cell = min(cell, beforeLast[column - 2] + 1)
                }
                current[column] = cell
                best = min(best, cell)
            }
            if best > budget { return budget + 1 }
            swap(&beforeLast, &last)
            swap(&last, &current)
        }
        return last.min() ?? budget + 1
    }

    /// Whether a candidate begins with exactly what was typed, which needs no edits at all.
    public static func isPrefix(_ query: [UInt8], of candidate: [UInt8]) -> Bool {
        candidate.count >= query.count && candidate.starts(with: query)
    }
}
