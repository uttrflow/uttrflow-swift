import UttrflowCore

/// Judges an answer as notation: its brackets and quotes must hold together with the caret's text. See `Docs/adapters.md` §5.
enum AdapterValidator {
    /// The verdict on `output` written at the caret of `situation`, judged only where the screen says notation is written.
    static func verdict(on output: String, in situation: Situation) -> AdapterVerdict {
        let screen = NotationEvidence.applicability(
            destination: situation.destination, region: situation.intent.region)
        guard screen.activates(at: NotationEvidence.activationThreshold) else { return .notApplicable }
        return balance(
            of: output, preceding: situation.insertion.precedingText ?? "",
            following: situation.insertion.followingText ?? "")
    }

    /// Whether `output` closes only what is open, accepting an open bracket and refusing a stray closer or unclosed quote.
    static func balance(of output: String, preceding: String, following: String) -> AdapterVerdict {
        var scan = BalanceScan()
        scan.read(preceding, asContext: true)
        scan.openedHere = false
        if let fault = scan.read(output, asContext: false) { return .malformed(reason: fault) }
        guard let quote = scan.quote, scan.openedHere else { return .wellFormed }
        let restOfLine = following.prefix { $0 != "\n" }
        return restOfLine.contains(quote) ? .wellFormed : .malformed(reason: "leaves a \(quote) quote open")
    }
}

/// The brackets and the quote open at one point of a left-to-right read.
private struct BalanceScan {
    /// Each bracket's closer, keyed by its opener.
    private static let closers: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    /// Each bracket's opener, keyed by its closer.
    private static let openers: [Character: Character] = [")": "(", "]": "[", "}": "{"]
    /// The quote characters a string can be written in.
    private static let quotes: Set<Character> = ["\"", "'", "`"]

    /// The openers not yet closed, innermost last.
    private var open: [Character] = []
    /// The quote the read stands inside, if any.
    private(set) var quote: Character?
    /// Whether that quote was opened by the text read last.
    var openedHere = false

    /// Reads `text` on from the current state, returning the first fault; context only sets state and ends quotes at a line break.
    @discardableResult
    mutating func read(_ text: String, asContext: Bool) -> String? {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if let current = quote {
                if character == "\\" {
                    index += 1
                } else if character == current || (asContext && character == "\n") {
                    quote = nil
                }
            } else if Self.quotes.contains(character) {
                if !Self.isApostrophe(at: index, in: characters) {
                    quote = character
                    openedHere = true
                }
            } else if Self.closers[character] != nil {
                open.append(character)
            } else if let opener = Self.openers[character] {
                if open.last == opener {
                    open.removeLast()
                } else if !asContext {
                    return open.last.map { "closes \($0) with \(character)" }
                        ?? "closes \(character) that nothing opened"
                }
            }
            index += 1
        }
        return nil
    }

    /// Whether the single quote at `index` sits between two letters, as in "don't", rather than opening a string.
    private static func isApostrophe(at index: Int, in characters: [Character]) -> Bool {
        guard characters[index] == "'", index > 0, index + 1 < characters.count else { return false }
        return characters[index - 1].isLetter && characters[index + 1].isLetter
    }
}
