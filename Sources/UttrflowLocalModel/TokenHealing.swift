private import Synchronization

/// Holds the first tokens of a pass to the word the person is in the middle of, so a line cut inside a token is continued rather than started over. See `Docs/predict-context.md`.
struct TokenHealing {
    /// Every token as the bytes it writes, read once per model, so a step can be masked by comparing bytes; a byte-fallback piece is its one byte, which is how an emoji or a mark is spelt.
    struct Vocabulary: Sendable {
        /// The UTF-8 bytes each token writes, by id, with the word-start mark read as the space it stands for.
        let bytes: [[UInt8]]
        /// The tokens that end a line or the turn, which a word just finished must not be followed by at once.
        let ending: Set<Int>
        /// Whether each token, by id, starts something new rather than lengthening the word before it, read once per model beside the bytes.
        let startsNewWord: [Bool]
        /// Token ids keyed by requested prefix length, built on demand.
        private let prefixIndex: PrefixIndex
        private let idsByBytes: [[UInt8]: [Int]]
        private let unrestricted: [Int]
        private let unrestrictedWordComplete: [Int]
        private let lookupCounter = LookupCounter()

        init(
            texts: [String], ending: Set<Int>, prefixIndex: PrefixIndex = PrefixIndex()
        ) {
            let byteLevelBPE = Self.usesByteLevelBPE(texts)
            self.init(
                bytes: texts.map { Self.bytes(of: $0, byteLevelBPE: byteLevelBPE) }, ending: ending,
                prefixIndex: prefixIndex)
        }

        init(
            bytes: [[UInt8]], ending: Set<Int>, prefixIndex: PrefixIndex = PrefixIndex()
        ) {
            self.bytes = bytes
            self.ending = ending
            self.prefixIndex = prefixIndex
            startsNewWord = bytes.map(Self.startsNewWord)
            var idsByBytes: [[UInt8]: [Int]] = [:]
            for (id, token) in bytes.enumerated() where !token.isEmpty {
                idsByBytes[token, default: []].append(id)
            }
            self.idsByBytes = idsByBytes
            unrestricted = bytes.indices.filter { id in
                let written = bytes[id]
                return !written.isEmpty && !ending.contains(id)
                    && written.contains { !Self.isSpace($0) }
            }
            unrestrictedWordComplete = unrestricted.filter { Self.isSpace(bytes[$0][0]) }
        }

        /// Tokens whose bytes start with `prefix`, without searching unrelated vocabulary entries.
        func ids(startingWith prefix: [UInt8]) -> [Int] {
            guard !prefix.isEmpty else { return [] }
            let ids = prefixIndex.ids(for: prefix, in: bytes)
            lookupCounter.entriesExamined.withLock { $0 += ids.count }
            return ids
        }

        /// Number of shared token-prefix indexes built so far.
        var prefixIndexBuilds: Int { prefixIndex.builds }

        /// The vocabulary entries inspected to answer indexed prefix lookups.
        var examinedEntries: Int { lookupCounter.entriesExamined.withLock { $0 } }

        /// Resets the lookup counter between operations under test.
        func resetExaminedEntries() { lookupCounter.entriesExamined.withLock { $0 = 0 } }

        /// Tokens whose complete byte sequence equals `written`.
        func ids(writing written: [UInt8]) -> [Int] { idsByBytes[written] ?? [] }

        /// Token ids whose bytes equal one of the supplied prefixes.
        func ids(writingAny prefixes: [[UInt8]]) -> [Int] {
            let ids = Set(prefixes.flatMap { idsByBytes[$0] ?? [] })
            lookupCounter.entriesExamined.withLock { $0 += ids.count }
            return ids.sorted()
        }

        /// The entries examined for each query are the matching ids only, never unrelated tokens.
        func continuing(_ prefix: [UInt8]) -> [Int] { ids(startingWith: prefix) }

        /// What a piece writes: the word-start mark as a space, and a byte-fallback piece such as `<0x0A>` as the one byte it names.
        static func bytes(of piece: String, byteLevelBPE: Bool = false) -> [UInt8] {
            if piece.count == 6, piece.hasPrefix("<0x"), piece.hasSuffix(">"),
                let byte = UInt8(piece.dropFirst(3).dropLast(), radix: 16)
            {
                return [byte]
            }
            let scalars = Array(piece.unicodeScalars)
            if byteLevelBPE || scalars.contains(where: ByteLevelBPE.isEscapedScalar) {
                let bytes = scalars.compactMap(ByteLevelBPE.byte(for:))
                if bytes.count == scalars.count { return bytes }
            }
            return Array(piece.replacingOccurrences(of: "\u{2581}", with: " ").utf8)
        }

        /// Whether any piece identifies the tokenizer's vocabulary as GPT-2 byte-level BPE.
        static func usesByteLevelBPE(_ pieces: [String]) -> Bool {
            pieces.contains { $0.unicodeScalars.contains(where: ByteLevelBPE.isEscapedScalar) }
        }

        /// Reverses the byte alphabet used by GPT-2 byte-level BPE vocabularies.
        private enum ByteLevelBPE {
            private static let escapedBytes: [UInt8] =
                Array(0...32).map { UInt8($0) }
                + [127] + Array(128...160).map { UInt8($0) } + [173]

            static func isEscapedScalar(_ scalar: Unicode.Scalar) -> Bool {
                (256..<(256 + escapedBytes.count)).contains(Int(scalar.value))
            }

            static func byte(for scalar: Unicode.Scalar) -> UInt8? {
                let value = Int(scalar.value)
                if value >= 256, value < 256 + escapedBytes.count {
                    return escapedBytes[value - 256]
                }
                if (33...126).contains(value) || (161...172).contains(value) || (174...255).contains(value) {
                    return UInt8(value)
                }
                return nil
            }
        }

        private final class LookupCounter: Sendable {
            let entriesExamined = Mutex(0)
        }

        /// Keeps queried prefix lengths across vocabulary reloads for one tokenizer.
        final class PrefixIndex: Sendable {
            private struct Storage {
                var idsByLength: [Int: [[UInt8]: [Int]]] = [:]
                var builds = 0
            }

            private let storage = Mutex(Storage())

            var builds: Int { storage.withLock { $0.builds } }

            func ids(for prefix: [UInt8], in bytes: [[UInt8]]) -> [Int] {
                let length = prefix.count
                let indexLength = min(length, 2)
                let candidates = storage.withLock { storage in
                    if storage.idsByLength[indexLength] == nil {
                        var idsByPrefix: [[UInt8]: [Int]] = [:]
                        for (id, token) in bytes.enumerated() where token.count >= indexLength {
                            idsByPrefix[Array(token.prefix(indexLength)), default: []].append(id)
                        }
                        storage.idsByLength[indexLength] = idsByPrefix
                        storage.builds += 1
                    }
                    return storage.idsByLength[indexLength]?[Array(prefix.prefix(indexLength))] ?? []
                }
                guard length > indexLength else { return candidates }
                return candidates.filter { bytes[$0].starts(with: prefix) }
            }
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

        /// The same token predicate as `allowed`, narrowed by exact bytes and prefix lookups when a remainder is owed.
        func allowedIDs(owing owed: [UInt8], wordComplete: Bool) -> [Int] {
            guard !owed.isEmpty else {
                return wordComplete ? unrestrictedWordComplete : unrestricted
            }
            var candidates = Set(ids(startingWith: owed))
            candidates.formUnion(ids(writingAny: (1...owed.count).map { Array(owed.prefix($0)) }))
            return candidates.filter { allowedToken($0, owing: owed, wordComplete: wordComplete) }.sorted()
        }

        /// Candidate vocabulary entries examined when constructing the current cache-hit rival set.
        private func allowedToken(_ id: Int, owing owed: [UInt8], wordComplete: Bool) -> Bool {
            let written = bytes[id]
            guard !written.isEmpty else { return false }
            if owed.isEmpty {
                return !ending.contains(id) && written.contains { !Self.isSpace($0) }
                    && (!wordComplete || Self.isSpace(written[0]))
            }
            return owed.starts(with: written) || (!wordComplete && written.starts(with: owed))
        }

        /// Whether a byte is a space or a tab, the whitespace a line can hold.
        static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }

        /// Whether a token starts something new rather than lengthening the word before it, which anything but a letter or digit at its front does.
        static func startsNewWord(_ written: [UInt8]) -> Bool {
            guard let first = String(decoding: written.prefix(4), as: UTF8.self).first else { return false }
            return !first.isLetter && !first.isNumber
        }
    }

    /// What a token starting a new word costs in logits at the step after a word the person stopped inside, so the word is lengthened unless the model is this much surer of a break. See `Docs/predict-context.md`.
    static let newWordPenalty: Float = 3

    let vocabulary: Vocabulary
    /// Whether the person finished the word with a space, so it is written exactly and what follows begins with one.
    let wordComplete: Bool
    /// Whether the line may end with the word, which a word closing a sentence or a statement does.
    let mayEnd: Bool
    /// What the model must still write before it is free: the rest of the typed word, then one visible character more.
    private(set) var owed: [UInt8]
    /// The indexed token ids that can still write the owed bytes.
    private var allowedIDs: [Int]
    /// Whether the word is complete and continued, after which every token is the model's own.
    private(set) var isFree = false
    /// Whether the person stopped inside a word, so a token starting a new word after it would split what they are typing.
    let isMidWord: Bool

    init(vocabulary: Vocabulary, owed: String, wordComplete: Bool, mayEnd: Bool = false) {
        self.vocabulary = vocabulary
        self.owed = Array(owed.utf8)
        allowedIDs = vocabulary.allowedIDs(owing: Array(owed.utf8), wordComplete: wordComplete)
        self.wordComplete = wordComplete
        self.mayEnd = mayEnd
        isMidWord = !wordComplete && (owed.last.map { $0.isLetter || $0.isNumber } ?? false)
    }

    /// What a step adds to the logits: nothing for an allowed token, minus infinity for the rest, and the new-word penalty where a break would split the typed word; nothing at all once the model is free or when no token could keep to the word.
    func mask(width: Int) -> [Float]? {
        guard !isFree else { return nil }
        let allowed = allowedIDs
        // With no token able to keep to the word, the model is left free rather than made to choose among nothing.
        guard !allowed.isEmpty else { return nil }
        // The typed word is written out, so this one step is where the model either lengthens it or breaks it.
        let maySplit = isMidWord && owed.isEmpty
        // The model's head may be wider than the vocabulary; the padding beyond it is never a token to pick.
        var mask = [Float](repeating: -.infinity, count: width)
        for id in allowed where id < width {
            mask[id] = maySplit && vocabulary.startsNewWord[id] ? -Self.newWordPenalty : 0
        }
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
            allowedIDs = []
            isFree = true
        } else if owed.starts(with: written) {
            owed.removeFirst(written.count)
            allowedIDs = vocabulary.allowedIDs(owing: owed, wordComplete: wordComplete)
            // A word that closes the line owes nothing more once written, so the model may stop there.
            if owed.isEmpty, mayEnd { isFree = true }
        } else {
            // A token the mask should have refused: the word cannot be held any longer, so the model is left free.
            owed = []
            allowedIDs = []
            isFree = true
        }
    }
}

/// Holds a pass to one of the machine's own values, so the model chooses among what exists and can write nothing else. See `Docs/predict-agent.md`.
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
        var candidates = Set<Int>()
        for choice in remaining {
            for length in 1...choice.count {
                candidates.formUnion(vocabulary.ids(writing: Array(choice.prefix(length))))
            }
            candidates.formUnion(vocabulary.ids(startingWith: choice + [0x20]))
            candidates.formUnion(vocabulary.ids(startingWith: choice + [0x09]))
        }
        let allowed = candidates.filter { Self.keeps(vocabulary.bytes[$0], toOneOf: remaining) }
        guard !allowed.isEmpty else { return nil }
        var mask = [Float](repeating: -.infinity, count: width)
        for id in allowed where id < width { mask[id] = 0 }
        return mask
    }

    /// Whether a token keeps to a choice: it writes part of one, or all of one and then a space.
    static func keeps(_ written: [UInt8], toOneOf choices: [[UInt8]]) -> Bool {
        guard !written.isEmpty else { return false }
        return choices.contains { choice in
            choice.starts(with: written)
                || (written.count > choice.count && written.starts(with: choice)
                    && TokenHealing.Vocabulary.isSpace(written[choice.count]))
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
