/// The English number words and the grammar that joins them into one value.
public enum NumberWords {
    public static let units = values(of: .unit)
    public static let teens = values(of: .teen)
    public static let tens = values(of: .ten)
    public static let scales = values(of: .scale)

    /// The bundled number words; a word is added by adding its row to `number-words.json`.
    static let table = DataTable<Row>.load("number-words", schema: 1, from: .module, fallback: [])

    private static func values(of rank: Rank) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: table.rows.filter { $0.rank == rank }.map { ($0.id, $0.value) })
    }

    /// Where a number word sits in the grammar that joins words into one value.
    enum Rank: String, Decodable, Sendable {
        case unit, teen, ten, scale
    }

    /// One number word, its value and its rank.
    struct Row: DataTableRow {
        let id: String
        let value: Int
        let rank: Rank
    }

    /// The value of a single number word, or nil for any other word.
    public static func value(of key: String) -> Int? {
        units[key] ?? teens[key] ?? tens[key] ?? scales[key]
    }

    /// The digit a word stands for when digits are read one at a time, where "oh" is zero.
    public static func spokenDigit(_ key: String) -> Int? {
        key == "oh" ? 0 : units[key]
    }

    /// Whether a word is a number, spoken or already in digits.
    public static func isNumber(_ key: String) -> Bool {
        value(of: key) != nil || digits(key) != nil
    }

    /// The key when it is already a numeral such as 15, 16.2 or 2:30.
    public static func digits(_ key: String) -> String? {
        guard let first = key.first, let last = key.last, first.isNumber, last.isNumber,
            key.allSatisfy({ $0.isNumber || ".,:".contains($0) })
        else { return nil }
        return key
    }

    /// Reads the longest cardinal number at the start of `keys`, saying how many words it used.
    public static func cardinal(_ keys: ArraySlice<String>) -> (value: Int, count: Int)? {
        var total = 0
        var group = 0
        var hasTens = false
        var hasUnits = false
        var hasHundred = false
        var lastScale = Int.max
        var consumed = 0
        var index = keys.startIndex
        while index < keys.endIndex {
            let key = keys[index]
            var next = keys.index(after: index)
            if key == "and", consumed > 0, group == 0 || (hasHundred && !hasTens && !hasUnits),
                next < keys.endIndex,
                units[keys[next]] != nil || teens[keys[next]] != nil
                    || tens[keys[next]] != nil
            {
                index = next
                continue
            }
            if let unit = units[key] {
                if hasUnits || (unit == 0 && consumed > 0) { break }
                group += unit
                hasUnits = true
                if unit == 0 { consumed = 1; break }
            } else if let teen = teens[key] {
                if hasTens || hasUnits { break }
                group += teen
                hasUnits = true
            } else if let ten = tens[key] {
                if hasTens || hasUnits { break }
                group += ten
                hasTens = true
            } else if key == "hundred" {
                if group == 0 || hasHundred { break }
                group *= 100
                hasHundred = true
                hasTens = false
                hasUnits = false
            } else if let scale = scales[key] {
                if group == 0 || scale >= lastScale { break }
                total += group * scale
                group = 0
                hasTens = false
                hasUnits = false
                hasHundred = false
                lastScale = scale
            } else {
                break
            }
            next = keys.index(after: index)
            consumed = keys.distance(from: keys.startIndex, to: next)
            index = next
        }
        guard consumed > 0 else { return nil }
        return (total + group, consumed)
    }

    /// A hundreds digit said before a number from ten to ninety-nine, as in "one twenty seven" for 127.
    public static func colloquialHundred(_ keys: ArraySlice<String>) -> (value: Int, count: Int)? {
        guard let first = keys.first, let digit = units[first], digit > 0,
            let rest = cardinal(keys.dropFirst()), (10...99).contains(rest.value)
        else { return nil }
        return (digit * 100 + rest.value, rest.count + 1)
    }

    /// Digits grouped with commas as `grouping` says, applied only from ten thousand up.
    public static func render(_ value: Int, grouping: DigitGrouping) -> String {
        let plain = String(value)
        guard let sizes = grouping.groupSizes, value >= 10_000 else { return plain }
        var out = ""
        var nextComma = sizes.last
        for (offset, character) in plain.reversed().enumerated() {
            if offset == nextComma {
                out.append(",")
                nextComma += sizes.rest
            }
            out.append(character)
        }
        return String(out.reversed())
    }
}
