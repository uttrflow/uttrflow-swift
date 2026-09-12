/// The English number words and the grammar that joins them into one value.
public enum NumberWords {
    public static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9,
    ]
    public static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    public static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
    ]
    public static let scales: [String: Int] = ["hundred": 100, "thousand": 1_000, "million": 1_000_000]

    /// The value of a single number word, or nil for any other word.
    public static func value(of key: String) -> Int? {
        units[key] ?? teens[key] ?? tens[key] ?? scales[key]
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

    /// Digits grouped in threes with commas, applied only from ten thousand up.
    public static func render(_ value: Int, grouped: Bool) -> String {
        let plain = String(value)
        guard grouped, value >= 10_000 else { return plain }
        var out = ""
        for (offset, character) in plain.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { out.append(",") }
            out.append(character)
        }
        return String(out.reversed())
    }
}
