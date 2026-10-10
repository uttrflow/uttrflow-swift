// Keeps a model's line from adding a number, an amount, an address or a credential nobody gave it.

import Foundation
import OSLog
import UttrflowCore
import UttrflowPredict

/// The specifics a model's line adds, and whether each one is grounded in what the person or the screen already holds.
enum Specifics {
    /// What kind of value a token names, so unrelated evidence cannot ground it.
    enum Kind: Hashable { case address, amount, credential, date, number, time }

    /// A normalised specific and the kind its surrounding words give it.
    struct Mention: Hashable {
        let token: String
        let kind: Kind
    }

    /// Where a refused line is counted, by reason and never by its words.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    /// Whether every specific the line adds after what was typed appears, token for token, in the typed text, the person's lines, the screen or the machine's values.
    static func areGrounded(
        _ line: String, typed: String, in situation: GenerationSituation, writesCode: Bool = false
    ) -> Bool {
        let added = specifics(in: line, after: typed, writesCode: writesCode)
        guard !added.isEmpty else { return true }
        let sources =
            [typed, situation.preceding, situation.surroundings, situation.document, situation.windowTitle]
            .compactMap { $0 } + situation.recentLines + situation.choices
        let known = Set(sources.flatMap { mentions(in: $0, writesCode: writesCode) })
        guard added.allSatisfy(known.contains) else {
            log.debug("DROP made-up specific")
            return false
        }
        return true
    }

    /// The numbers code writes that carry no value of their own: nothing, one, the last one, as an initialiser, an index, a bound or a step. See `Docs/predict-precision.md`.
    static let conventionalNumbers: Set<String> = ["0", "1", "-1", "0.0", "1.0"]

    /// The last words of a name that says its value picks out one record, so even a conventional number there is an invented id.
    static let keyWords: Set<String> = ["id", "ids", "pid", "uid", "uuid", "guid"]

    /// Entity names whose first call argument identifies a record, whatever the call does to it.
    static let recordEntityNames: Set<String> = ["user", "order", "account", "record", "item"]

    /// Whether a specific token of code is so only by numbers that are each conventional and none a chosen value.
    static func isConventionalCode(_ token: String, word: Substring, after before: Substring) -> Bool {
        guard !namesAddressOrAmount(token), !namesCredential(String(word)) else { return false }
        let characters = Array(before) + Array(word)
        var index = before.count
        while index < characters.count {
            let previous = index > 0 ? characters[index - 1] : nil
            guard characters[index].isNumber, !(previous.map(isAlphanumeric) ?? false) else {
                index += 1
                continue
            }
            var end = index
            while end < characters.count, isAlphanumeric(characters[end]) || "._".contains(characters[end]) {
                end += 1
            }
            var literal = String(characters[index..<end])
            while literal.hasSuffix(".") { literal.removeLast() }
            var start = index
            // A minus sign after a name or a number subtracts; anywhere else it is the literal's own sign.
            if previous == "-", index < 2 || !isAlphanumeric(characters[index - 2]) {
                literal = "-" + literal
                start -= 1
            }
            guard conventionalNumbers.contains(literal), isOperand(at: start, in: characters),
                !isChosenValue(at: start, in: characters)
            else {
                return false
            }
            index = end
        }
        return true
    }

    /// The characters after which a number is an operand of code: an assignment, a bracket, a separator, an operator or a member.
    static let operandOpeners: Set<Character> = [
        "=", "(", "[", "{", ",", ":", ";", "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", "?", ".", "$",
    ]

    /// The words after which a number is an operand of code or a query rather than an argument a command acts on.
    static let operandKeywords: Set<String> = [
        "return", "in", "case", "yield", "else", "then", "when", "and", "or", "not", "is", "of", "to", "step",
        "limit", "offset", "select", "top",
    ]

    /// Whether the number at this offset is an operand of code, as in `= 0` or `return 1`, and not an argument a command acts on, as in `kill 1` or `HEAD~1`.
    static func isOperand(at start: Int, in characters: [Character]) -> Bool {
        var index = start
        while index > 0, " \t\"'`".contains(characters[index - 1]) { index -= 1 }
        guard index > 0 else { return false }
        if operandOpeners.contains(characters[index - 1]) { return true }
        var wordStart = index
        while wordStart > 0, isAlphanumeric(characters[wordStart - 1]) || characters[wordStart - 1] == "_" {
            wordStart -= 1
        }
        guard wordStart < index, wordStart == 0 || " \t".contains(characters[wordStart - 1]) else {
            return false
        }
        return operandKeywords.contains(String(characters[wordStart..<index]).lowercased())
    }

    /// Whether the number at this offset is a threshold, as `> 0` is, or the value of a name whose last word says it is an id, as `id = 1` and `userId: 0` are and `ids[0]` is not.
    static func isChosenValue(at start: Int, in characters: [Character]) -> Bool {
        var index = start
        var operates = false
        while index > 0, " \t=!<>:\"'`".contains(characters[index - 1]) {
            if "<>".contains(characters[index - 1]) { return true }
            if "=!:".contains(characters[index - 1]) { operates = true }
            index -= 1
        }
        if !operates, let open = openingParenthesis(before: index, in: characters) {
            let firstArgument = characters[(open + 1)..<index].allSatisfy { $0.isWhitespace }
            return namesKey(endingAt: open, in: characters, throughIn: true)
                || (firstArgument && namesEntityCall(endingAt: open, in: characters))
        }
        guard operates else { return false }
        return namesKey(endingAt: index, in: characters, throughIn: false)
    }

    /// Where the `(` of an argument list stands when this offset is inside it after `(` or `, `, as in `byId(1)` and `IN (0, 1)`.
    static func openingParenthesis(before end: Int, in characters: [Character]) -> Int? {
        var index = end
        while index > 0 {
            let character = characters[index - 1]
            if character == "(" { return index - 1 }
            guard isAlphanumeric(character) || " \t,._-\"'".contains(character) else { return nil }
            index -= 1
        }
        return nil
    }

    /// Whether the name that ends at this offset, or the column before an `IN` there, has an id word as its last, as `findById` and `user_id IN` do.
    static func namesKey(endingAt end: Int, in characters: [Character], throughIn: Bool) -> Bool {
        var index = end
        while index > 0, " \t".contains(characters[index - 1]) { index -= 1 }
        var nameStart = index
        while nameStart > 0, isAlphanumeric(characters[nameStart - 1]) || characters[nameStart - 1] == "_" {
            nameStart -= 1
        }
        let name = String(characters[nameStart..<index])
        if throughIn, name.lowercased() == "in" {
            var columnEnd = nameStart
            while columnEnd > 0, " \t".contains(characters[columnEnd - 1]) { columnEnd -= 1 }
            var operatorStart = columnEnd
            while operatorStart > 0, isAlphanumeric(characters[operatorStart - 1]) {
                operatorStart -= 1
            }
            if String(characters[operatorStart..<columnEnd]).lowercased() == "not" {
                return namesKey(endingAt: operatorStart, in: characters, throughIn: false)
            }
            return namesKey(endingAt: nameStart, in: characters, throughIn: false)
        }
        guard let last = words(of: name).last else { return false }
        return keyWords.contains(last)
    }

    /// Whether the call name ends with a record entity, regardless of its verb.
    static func namesEntityCall(endingAt end: Int, in characters: [Character]) -> Bool {
        var index = end
        while index > 0, " \t".contains(characters[index - 1]) { index -= 1 }
        var nameStart = index
        while nameStart > 0, isAlphanumeric(characters[nameStart - 1]) || characters[nameStart - 1] == "_" {
            nameStart -= 1
        }
        let name = String(characters[nameStart..<index])
        guard let entity = words(of: name).last else { return false }
        return recordEntityNames.contains(entity)
    }

    /// Whether a character is a letter or a digit, which is what a name or a number is made of.
    static func isAlphanumeric(_ character: Character) -> Bool { character.isLetter || character.isNumber }

    /// The words of a name split at underscores and at each lowercase-to-uppercase step, lowercased.
    static func words(of name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in name {
            if character == "_" || (character.isUppercase && previous?.isLowercase == true) {
                if !current.isEmpty { words.append(current.lowercased()) }
                current = ""
            }
            if character != "_" { current.append(character) }
            previous = character
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }

    /// A word lowercased with the punctuation around it dropped, or nothing when no character is left.
    static func normalised(_ word: Substring) -> String? {
        let edges = CharacterSet(charactersIn: ".,;:!?()[]{}\"'`<>*")
        let token = word.trimmingCharacters(in: edges).lowercased()
        return token.isEmpty ? nil : token
    }

    /// Whether a token names an email, a web address, an amount or a percentage, which no register writes as a convention.
    static func namesAddressOrAmount(_ token: String) -> Bool {
        if token.contains("@"), token.count > 1 { return true }
        if token.contains("://") || token.hasPrefix("www.") || isHostPath(token) || isBareHost(token) {
            return true
        }
        return token.contains(where: isAmountSign)
    }

    /// Whether a token is a credential under the shared secret-shape rules.
    static func namesCredential(_ token: String) -> Bool {
        SecretShapes.matches(token)
    }

    /// Whether every label of a dotted token has a plausible DNS host shape.
    static func isBareHost(_ token: String) -> Bool {
        let labels = token.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, let suffix = labels.last, suffix.count >= 2,
            suffix.contains(where: \.isLetter), token.utf8.count <= 253,
            labels.allSatisfy({ $0.utf8.count <= 63 })
        else { return false }
        return labels.allSatisfy { label in
            guard let first = label.first, let last = label.last,
                first.isLetter, last.isLetter || last.isNumber
            else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    /// Whether some digit in the token opens a run of digits no letter stands before, as in `3pm`, `#12` or `12.50`, never `python3`.
    static func startsANumber(_ token: String) -> Bool {
        var previous: Character?
        for character in token {
            if character.isNumber, previous.map({ !$0.isLetter && !$0.isNumber }) ?? true { return true }
            previous = character
        }
        return false
    }

    /// Whether a character marks an amount or a share: a currency sign or a percent sign.
    static func isAmountSign(_ character: Character) -> Bool {
        character == "%"
            || character.unicodeScalars.contains { $0.properties.generalCategory == .currencySymbol }
    }

    /// Whether the token is a dotted host followed by a path, as `github.com/org` is and `docs/guide.md` is not.
    static func isHostPath(_ token: String) -> Bool {
        guard let slash = token.firstIndex(of: "/") else { return false }
        let host = token[..<slash]
        guard let dot = host.lastIndex(of: "."), dot != host.startIndex else { return false }
        let domain = host[host.index(after: dot)...]
        return domain.count >= 2 && domain.allSatisfy(\.isLetter)
    }
}
