/// Holds the first tokens of a pass to the word the person is in the middle of, so a line cut inside a token is continued rather than started over. See `Docs/predict-context.md`, G5.
struct TokenHealing {
    /// Every token as the bytes it writes, read once per model, so a step can be masked by comparing bytes; a byte-fallback piece is its one byte, which is how an emoji or a mark is spelt.
    struct Vocabulary: Sendable {
        /// The UTF-8 bytes each token writes, by id, with the word-start mark read as the space it stands for.
        let bytes: [[UInt8]]
        /// The tokens that end a line or the turn, which a word just finished must not be followed by at once.
        let ending: Set<Int>

        init(texts: [String], ending: Set<Int>) {
            self.init(bytes: texts.map { Array($0.utf8) }, ending: ending)
        }

        init(bytes: [[UInt8]], ending: Set<Int>) {
            self.bytes = bytes
            self.ending = ending
        }

        /// What a piece writes: the word-start mark as a space, and a byte-fallback piece such as `<0x0A>` as the one byte it names.
        static func bytes(of piece: String) -> [UInt8] {
            if piece.count == 6, piece.hasPrefix("<0x"), piece.hasSuffix(">"),
                let byte = UInt8(piece.dropFirst(3).dropLast(), radix: 16)
            {
                return [byte]
            }
            return Array(piece.replacingOccurrences(of: "\u{2581}", with: " ").utf8)
        }

        /// The tokens a step may produce: those that keep to what is owed, or when nothing is owed any that adds a visible character without ending the line; a word the person finished is never overshot, and what follows it begins with a space.
        func allowed(owing owed: [UInt8], wordComplete: Bool) -> [Bool] {
            bytes.indices.map { id in
                let written = bytes[id]
                guard !written.isEmpty else { return false }
                if owed.isEmpty {
                    return !ending.contains(id) && written.contains { !Self.isSpace($0) }
                        && (!wordComplete || Self.isSpace(written[0]))
                }
                return owed.starts(with: written) || (!wordComplete && written.starts(with: owed))
            }
        }

        /// Whether a byte is a space or a tab, the whitespace a line can hold.
        static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }
    }

    let vocabulary: Vocabulary
    /// Whether the person finished the word with a space, so it is written exactly and what follows begins with one.
    let wordComplete: Bool
    /// Whether the line may end with the word, which a word closing a sentence or a statement does.
    let mayEnd: Bool
    /// What the model must still write before it is free: the rest of the typed word, then one visible character more.
    private(set) var owed: [UInt8]
    /// Whether the word is complete and continued, after which every token is the model's own.
    private(set) var isFree = false

    init(vocabulary: Vocabulary, owed: String, wordComplete: Bool, mayEnd: Bool = false) {
        self.vocabulary = vocabulary
        self.owed = Array(owed.utf8)
        self.wordComplete = wordComplete
        self.mayEnd = mayEnd
    }

    /// What a step adds to the logits: nothing for an allowed token, minus infinity for the rest; nothing at all once the model is free or when no token could keep to the word.
    func mask(width: Int) -> [Float]? {
        guard !isFree else { return nil }
        let allowed = vocabulary.allowed(owing: owed, wordComplete: wordComplete)
        // With no token able to keep to the word, the model is left free rather than made to choose among nothing.
        guard allowed.contains(true) else { return nil }
        // The model's head may be wider than the vocabulary; the padding beyond it is never a token to pick.
        var mask = [Float](repeating: -.infinity, count: width)
        for (id, isAllowed) in allowed.enumerated() where isAllowed && id < width { mask[id] = 0 }
        return mask
    }

    /// Advances what is owed by one token's text, kept apart from the model so a test can drive it.
    mutating func took(_ text: String) { took(Array(text.utf8)) }

    /// Advances what is owed by the bytes one token wrote.
    mutating func took(_ written: [UInt8]) {
        guard !owed.isEmpty else {
            // Only a visible character continues the line; a lone space would let the next token end it.
            isFree = written.contains { !Vocabulary.isSpace($0) }
            return
        }
        if written.count > owed.count, written.starts(with: owed) {
            owed = []
            isFree = true
        } else if owed.starts(with: written) {
            owed.removeFirst(written.count)
            // A word that closes the line owes nothing more once written, so the model may stop there.
            if owed.isEmpty, mayEnd { isFree = true }
        } else {
            // A token the mask should have refused: the word cannot be held any longer, so the model is left free.
            owed = []
            isFree = true
        }
    }
}

/// Holds a pass to one of the machine's own values, so the model chooses among what exists and can write nothing else. See `Docs/predict-agent.md`, A3.
struct TokenChoice {
    let vocabulary: TokenHealing.Vocabulary
    /// What remains to be written of each choice still open; a choice written whole frees the model.
    private(set) var remaining: [[UInt8]]
    /// Whether a choice has been written whole, after which every token is the model's own.
    private(set) var isFree = false

    init(vocabulary: TokenHealing.Vocabulary, choices: [String]) {
        self.vocabulary = vocabulary
        remaining = choices.map { Array($0.utf8) }.filter { !$0.isEmpty }
    }

    /// What a step adds to the logits: nothing for a token that keeps to some choice, minus infinity for the rest; nothing at all once a choice is written or when no token could keep to one.
    func mask(width: Int) -> [Float]? {
        guard !isFree else { return nil }
        let allowed = vocabulary.bytes.indices.map { id in
            Self.keeps(vocabulary.bytes[id], toOneOf: remaining)
        }
        guard allowed.contains(true) else { return nil }
        var mask = [Float](repeating: -.infinity, count: width)
        for (id, isAllowed) in allowed.enumerated() where isAllowed && id < width { mask[id] = 0 }
        return mask
    }

    /// Whether a token keeps to a choice: it writes part of one, or all of one and then a space.
    static func keeps(_ written: [UInt8], toOneOf choices: [[UInt8]]) -> Bool {
        guard !written.isEmpty else { return false }
        return choices.contains { choice in
            choice.starts(with: written)
                || (written.starts(with: choice) && TokenHealing.Vocabulary.isSpace(written[choice.count]))
        }
    }

    /// Advances every choice by the bytes one token wrote, dropping those it left; a choice written whole frees the model.
    mutating func took(_ written: [UInt8]) {
        guard !isFree else { return }
        var still: [[UInt8]] = []
        for choice in remaining {
            if choice.starts(with: written) {
                still.append(Array(choice.dropFirst(written.count)))
            } else if written.starts(with: choice) {
                still.append([])
            }
        }
        remaining = still
        // A choice written whole, or a token the mask should have refused, leaves nothing to hold the model to.
        if still.isEmpty || still.contains(where: \.isEmpty) { isFree = true }
    }

    /// Advances by one token's text, kept apart from the model so a test can drive it.
    mutating func took(_ text: String) { took(Array(text.utf8)) }
}
