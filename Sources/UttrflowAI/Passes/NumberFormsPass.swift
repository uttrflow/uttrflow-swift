public import UttrflowCore

/// Writes spoken numbers as numerals, as many of them as the place asks for. See `Docs/cleanup.md`.
public struct NumberFormsPass: CleaningPass {
    public static let id: PassID = .numberForms

    /// Which spoken numbers this place wants as numerals.
    let policy: NumberPolicy

    /// Words after which a lone digit is a numeral, digit groups run together, and no separator is used.
    static let contextWords: Set<String> = [
        "port", "version", "extension", "page", "chapter", "step", "number", "line", "section", "figure",
        "table", "level", "room", "floor",
    ]
    static let meridiems: Set<String> = ["am", "pm", "a.m", "p.m"]

    /// One rendered number and how many words it replaces.
    struct Phrase: Equatable {
        let text: String
        let count: Int
    }

    /// A number as spoken or already in digits, before anything joins onto it.
    private struct Item {
        let value: Int?
        let text: String
        let count: Int
        let spoken: Bool
    }

    public init(policy: NumberPolicy = .fromTen) {
        self.policy = policy
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        let shapes = live.map { draft.shape(at: $0) }
        var position = 0
        while position < live.count {
            guard let phrase = Self.phrase(at: position, in: shapes, policy: policy) else {
                position += 1
                continue
            }
            let last = position + phrase.count - 1
            let text = shapes[position].prefix + phrase.text + shapes[last].suffix
            draft.replace(at: live[position], with: text, by: Self.id)
            for index in live[(position + 1)..<(last + 1)] { draft.remove(at: index, by: Self.id) }
            position += phrase.count
        }
        return draft
    }

    /// The numeral for the number phrase starting at `position`, or nil when the words stay as they are.
    static func phrase(
        at position: Int, in shapes: [WordShape], policy: NumberPolicy = .fromTen
    ) -> Phrase? {
        let keys = shapes.map(\.key)
        guard let item = item(at: position, keys: keys, shapes: shapes) else { return nil }
        let inContext = position > 0 && contextWords.contains(keys[position - 1])
        var end = position + item.count
        var text = item.text
        var isPhrase = false

        while joined(end, shapes), keys[end] == "point",
            let group = digitGroup(at: end + 1, keys: keys, shapes: shapes)
        {
            text += "." + group.text
            end += 1 + group.count
            isPhrase = true
        }
        if joined(end, shapes), keys[end] == "percent" {
            text += "%"
            end += 1
            isPhrase = true
        } else if joined(end, shapes), keys[end] == "per", joined(end + 1, shapes), keys[end + 1] == "cent" {
            text += "%"
            end += 2
            isPhrase = true
        }
        if !isPhrase, let value = item.value, !inContext {
            if let year = year(after: value, at: end, keys: keys, shapes: shapes) {
                text = year.text
                end += year.count
                isPhrase = true
            } else if let time = time(hour: value, at: end, keys: keys, shapes: shapes) {
                text = time.text
                end += time.count
                isPhrase = true
            }
        }
        if !isPhrase, inContext, item.spoken {
            while joined(end, shapes),
                let group = NumberWords.cardinal(unbroken(from: end, keys: keys, shapes: shapes))
            {
                text += String(group.value)
                end += group.count
                isPhrase = true
            }
        }
        if !isPhrase, item.spoken, let value = item.value {
            guard policy == .always || inContext || value >= 10 else { return nil }
            text = NumberWords.render(value, grouped: !inContext)
        } else if !isPhrase {
            return nil
        }
        return Phrase(text: text, count: end - position)
    }

    private static func item(at position: Int, keys: [String], shapes: [WordShape]) -> Item? {
        if let digits = NumberWords.digits(keys[position]) {
            return Item(value: Int(digits), text: digits, count: 1, spoken: false)
        }
        guard let parsed = NumberWords.cardinal(unbroken(from: position, keys: keys, shapes: shapes)) else {
            return nil
        }
        return Item(value: parsed.value, text: String(parsed.value), count: parsed.count, spoken: true)
    }

    /// Whether the word at `index` follows its predecessor with no punctuation between them.
    private static func joined(_ index: Int, _ shapes: [WordShape]) -> Bool {
        index < shapes.count && shapes[index - 1].suffix.isEmpty && shapes[index].prefix.isEmpty
    }

    /// The keys from `start` up to the first word that carries punctuation.
    private static func unbroken(from start: Int, keys: [String], shapes: [WordShape]) -> ArraySlice<String> {
        var end = start
        while end < keys.count, end == start || joined(end, shapes) {
            end += 1
            if !shapes[end - 1].suffix.isEmpty { break }
        }
        return keys[start..<end]
    }

    /// The digits after "point": single digits run together, or one number from ten up.
    private static func digitGroup(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        var text = ""
        var end = start
        while joined(end, shapes), let digit = singleDigit(keys[end]) {
            text.append(digit)
            end += 1
        }
        if !text.isEmpty { return Phrase(text: text, count: end - start) }
        guard joined(start, shapes) else { return nil }
        if let digits = NumberWords.digits(keys[start]) { return Phrase(text: digits, count: 1) }
        guard let group = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            group.value >= 10
        else { return nil }
        return Phrase(text: String(group.value), count: group.count)
    }

    private static func singleDigit(_ key: String) -> String? {
        if key == "oh" { return "0" }
        return NumberWords.units[key].map(String.init)
    }

    /// "twenty twenty four" and "nineteen ninety nine", from a spoken 19 or 20 and a spoken 10 to 99.
    private static func year(
        after century: Int, at start: Int, keys: [String], shapes: [WordShape]
    ) -> Phrase? {
        guard century == 19 || century == 20, joined(start, shapes),
            let rest = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            (10...99).contains(rest.value), rest.count <= 2
        else { return nil }
        return Phrase(text: String(century * 100 + rest.value), count: rest.count)
    }

    /// "two thirty", "two thirty pm", "two oh five pm", "ten am", "five o'clock"; am and pm stay separate.
    private static func time(hour: Int, at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        guard (1...12).contains(hour), joined(start, shapes) else { return nil }
        if let minutes = minutes(at: start, keys: keys, shapes: shapes) {
            return Phrase(text: "\(hour):\(minutes.text)", count: minutes.count)
        }
        guard meridiems.contains(keys[start]) || keys[start] == "o'clock" else { return nil }
        return Phrase(text: String(hour), count: 0)
    }

    private static func minutes(at start: Int, keys: [String], shapes: [WordShape]) -> Phrase? {
        if keys[start] == "oh" || keys[start] == "zero", joined(start + 1, shapes),
            let digit = NumberWords.units[keys[start + 1]], digit > 0
        {
            return Phrase(text: "0\(digit)", count: 2)
        }
        guard let group = NumberWords.cardinal(unbroken(from: start, keys: keys, shapes: shapes)),
            (10...59).contains(group.value), group.count <= 2
        else { return nil }
        return Phrase(text: String(group.value), count: group.count)
    }
}
