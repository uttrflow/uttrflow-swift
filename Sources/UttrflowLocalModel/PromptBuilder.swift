import UttrflowPredict

/// What one pass asks the model for: the one line the person waits for, or the others behind it.
enum Ask: Equatable, Sendable {
    /// The single most likely way to finish the line, on one line.
    case one
    /// Up to three other ways, none of them the line already on screen.
    case others(excluding: String)

    /// The decoded text that ends the pass: the newline after one line, or nothing when several lines are wanted.
    var stopStrings: Set<String>? { self == .one ? ["\n"] : nil }

    /// How the model's turn opens when one line is wanted: the line up to its last word written for it, and that word still owed.
    struct Opening: Equatable {
        /// What is put into the model's turn before it writes, so the answer can only continue the line.
        let written: String
        /// The last word with the space before it, which the model must write again token by token before it is free.
        let owed: String
        /// Whether the person finished that word with a space, so it must not be lengthened and what follows begins with one.
        let isWordComplete: Bool

        /// Whether the line may end with the word: it closes with a full stop, a question or exclamation mark or a semicolon and nothing was typed after, so the model is free to stop.
        var mayEnd: Bool {
            guard !isWordComplete, let last = owed.last else { return false }
            return ".!?;".contains(last)
        }
    }

    /// The opening for one line, or nothing for several lines, which must each repeat the line.
    func opening(of typed: String) -> Opening? {
        guard self == .one, let last = typed.lastIndex(where: { !$0.isWhitespace }) else { return nil }
        let line = typed[...last]
        // The last word is the model's to write again: cut mid-token it cannot be continued, and finished it invites a newline.
        var start = line.lastIndex(where: \.isWhitespace).map { line.index(after: $0) } ?? line.startIndex
        while start > line.startIndex, line[line.index(before: start)].isWhitespace {
            start = line.index(before: start)
        }
        let owed = String(line[start...])
        return Opening(
            written: String(line[..<start]), owed: owed,
            isWordComplete: last < typed.index(before: typed.endIndex))
    }
}

/// Lays one moment out for the model under a fixed token budget for its context, the line itself never touched. See `Docs/predict-context.md`.
enum PromptBuilder {
    /// The most tokens the context around the line may take, headings included; prefilling it is the bulk of a pass, so this is the lever.
    static let contextBudgetInTokens = 160

    /// The most of that budget the screen may take, since a page's text is the context least likely to be the line's.
    static let screenBudgetInTokens = 96

    /// Once the field's own text before the line is this long it says enough, and the screen is not shown at all.
    static let ownTextSufficesInTokens = 64

    /// A window title, field name or document longer than this names nothing more, and the rest is the context's.
    static let locatorCap = 80

    /// What a heading and the blank lines around it add to a part of the context, in tokens.
    static let headingCost = 16

    /// What the model is told when the context holds another script: the line is written in English, or romanised Hinglish, in the Latin alphabet. See `Docs/predict.md`.
    static let scriptInstruction =
        "Write only English in the Latin alphabet, or romanised Hinglish where the person writes Hindi in Latin "
        + "letters. Never write Devanagari or any other script, and never translate."

    /// The whole message: where the caret is, the register, what is around it, how this person writes here, the line.
    static func message(
        typed: String, in situation: GenerationSituation, register: Register, asking ask: Ask = .one
    ) -> String {
        var located = "application \(situation.application)"
        if let title = situation.windowTitle {
            located += ", window \"\(Self.head(title, within: locatorCap))\""
        }
        if let field = situation.field { located += ", field \(Self.head(field, within: locatorCap))" }
        if let document = situation.document {
            located += ", document \(Self.head(document, within: locatorCap))"
        }
        var opening = "In \(located).\nHints: \(register.hints.joined(separator: "; "))."
        // Adds the script instruction only when the context shows another script. See `Docs/predict.md`.
        if !situation.readsOnlyLatin { opening += "\n\(scriptInstruction)" }
        // The machine's own values are the only right next words, so the model is told them and chooses rather than invents.
        if ask == .one, !situation.choices.isEmpty {
            opening +=
                "\nThe next word is one of these, exactly as written: \(situation.choices.joined(separator: ", "))."
        }
        let closing =
            switch ask {
            case .one:
                "\(Self.instruction(for: register)):\n\(typed)"
            case .others(let leader):
                "Give up to three other ways to finish this \(register.kind), each different from \"\(leader)\", "
                    + "one per line:\n\(typed)"
            }

        let context = Self.context(for: situation)
        var parts = [opening]
        if !context.screen.isEmpty {
            parts.append("On screen around the field:\n\(context.screen)")
        }
        if !context.recent.isEmpty {
            parts.append("Lines this person wrote here before:\n\(context.recent)")
        }
        if !context.preceding.isEmpty {
            parts.append("The text before the line reads:\n\(context.preceding)")
        }
        parts.append(closing)
        return parts.joined(separator: "\n\n")
    }

    /// The context parts as they are shown: nearest the line kept first, the field's own text before the person's lines before the screen.
    static func context(
        for situation: GenerationSituation
    ) -> (screen: String, recent: String, preceding: String) {
        var remaining = contextBudgetInTokens
        let preceding = situation.preceding.map { Self.tail($0, within: remaining / 2 - headingCost) } ?? ""
        remaining -= Self.cost(of: preceding)
        let recent = Self.newest(situation.recentLines, within: remaining / 2 - headingCost).joined(
            separator: "\n")
        remaining -= Self.cost(of: recent)
        // A field that already holds a paragraph of its own is its own best context, and the page would only slow the pass.
        let screen =
            estimatedTokens(preceding) >= ownTextSufficesInTokens
            ? ""
            : situation.surroundings.map {
                Self.nearestLines($0, within: min(remaining, screenBudgetInTokens) - headingCost)
            } ?? ""
        return (screen, recent, preceding)
    }

    /// The instruction at the line for one completion: it names the register's kind, and asks a reply to be finished whole rather than by a word.
    static func instruction(for register: Register) -> String {
        let ask = "Continue this \(register.kind) with the single most likely completion, on one line"
        return register.isConversational ? ask + ", finishing the whole message" : ask
    }

    /// What a part takes from the budget: its tokens and its heading, or nothing once it has trimmed to nothing.
    private static func cost(of part: String) -> Int {
        part.isEmpty ? 0 : estimatedTokens(part) + headingCost
    }

    /// About how many tokens Gemma's vocabulary spends on the text, erring high: a word of letters per four, a digit, mark or newline each one.
    static func estimatedTokens(_ text: some StringProtocol) -> Int {
        var tokens = 0
        var latin = 0
        var other = 0
        var spaces = 0
        func settle() {
            tokens += (latin + 3) / 4 + (other + 1) / 2 + (spaces > 1 ? 1 : 0)
            latin = 0
            other = 0
        }
        for scalar in text.unicodeScalars {
            if scalar.isASCII, scalar.properties.isAlphabetic {
                if spaces > 0 { settle() }
                spaces = 0
                latin += 1
            } else if !scalar.isASCII, scalar.properties.isAlphabetic || Self.isMark(scalar) {
                if spaces > 0 { settle() }
                spaces = 0
                other += 1
            } else if scalar == " " || scalar == "\t" {
                if spaces == 0 { settle() }
                spaces += 1
            } else {
                settle()
                // A space before a digit or a mark is a token of its own, since no word takes it.
                tokens += spaces == 1 ? 2 : 1
                spaces = 0
            }
        }
        settle()
        return tokens
    }

    /// Whether the scalar is a combining mark, which belongs to the letter before it as a vowel sign does.
    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    /// The start of the text, which is where a title or a name says what it is, cut to the allowance in characters.
    static func head(_ text: String, within allowance: Int) -> String {
        guard allowance > 0 else { return "" }
        return text.count > allowance ? String(text.prefix(allowance)) : text
    }

    /// The longest end of the text whose estimate fits the allowance in tokens, which is the part nearest the line.
    static func tail(_ text: String, within allowance: Int) -> String {
        guard allowance > 0 else { return "" }
        guard estimatedTokens(text) > allowance else { return text }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if estimatedTokens(String(characters[(characters.count - mid)...])) <= allowance {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(characters[(characters.count - low)...])
    }

    /// The longest start of the text whose estimate fits the allowance in tokens.
    static func leading(_ text: String, within allowance: Int) -> String {
        guard allowance > 0 else { return "" }
        guard estimatedTokens(text) > allowance else { return text }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if estimatedTokens(String(characters[..<mid])) <= allowance { low = mid } else { high = mid - 1 }
        }
        return String(characters[..<low])
    }

    /// The newest lines that fit the allowance in tokens, oldest dropped first, and the newest alone cut down when even it does not fit.
    static func newest(_ lines: [String], within allowance: Int) -> [String] {
        var kept: [String] = []
        var used = 0
        for line in lines {
            let cost = estimatedTokens(line) + 1
            guard used + cost <= allowance else { break }
            kept.append(line)
            used += cost
        }
        if kept.isEmpty, let first = lines.first, allowance > 1 {
            let cut = Self.leading(first, within: allowance - 1)
            return cut.isEmpty ? [] : [cut]
        }
        return kept
    }

    /// The screen's lines nearest the field that fit the allowance in tokens, each said once, in reading order; the nearest alone keeps its end when it does not fit.
    static func nearestLines(_ screen: String, within allowance: Int) -> String {
        guard allowance > 1 else { return "" }
        var seen: Set<Substring> = []
        var kept: [String] = []
        var used = 0
        for line in screen.split(whereSeparator: \.isNewline).reversed() {
            var text = line
            while text.first?.isWhitespace == true { text.removeFirst() }
            while text.last?.isWhitespace == true { text.removeLast() }
            // A control repeated down a page, as "Reply" under every comment is, is said once, nearest the field.
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            let cost = estimatedTokens(text) + 1
            guard used + cost <= allowance else {
                if kept.isEmpty { kept.append(Self.tail(String(text), within: allowance - 1)) }
                break
            }
            kept.append(String(text))
            used += cost
        }
        return kept.reversed().filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
