import UttrflowCore
import UttrflowDictionary

// The guard's survival and word-order checks and the word-occurrence index they share.
extension MeaningPreservationGuard {
    /// Refuses a word the model moved, using the shared word alignment while leaving edits to the other guard checks.
    static func wordOrderVerdict(kept: [GrammarToken], written: [GrammarToken]) -> GuardVerdict {
        let alignment = WordErrorRate.measure(
            reference: kept.filter(\.isPlain).map(\.matching),
            hypothesis: written.filter(\.isPlain).map(\.matching))
        var deleted: Set<String> = []
        var inserted: Set<String> = []
        var substitutedFrom: Set<String> = []
        var substitutedTo: Set<String> = []
        for operation in alignment.alignment {
            switch operation {
            case .match:
                break
            case .deletion(let word):
                deleted.insert(word)
            case .insertion(let word):
                inserted.insert(word)
            case .substitution(let reference, let hypothesis):
                substitutedFrom.insert(reference)
                substitutedTo.insert(hypothesis)
            }
        }
        guard deleted.isDisjoint(with: inserted), substitutedFrom.isDisjoint(with: substitutedTo) else {
            return .rejected(reason: "the rewrite moved a word", kind: .movedWord)
        }
        return .accepted
    }

    /// Walks the kept content words along the rewrite, so a word may change its form but never its place.
    static func survivalVerdict(
        _ kept: [GrammarToken], in written: [GrammarToken], allowingRomanisedHindiSpellings: Bool = false
    ) -> GuardVerdict {
        var reached = 0
        var index = 0
        while index < kept.count {
            let token = kept[index]
            if index + 1 < kept.count, Self.symbolNames[kept[index + 1].matching] != nil {
                guard index + 2 < kept.count else {
                    return .rejected(
                        reason: "the rewrite lost or replaced '\(kept[index + 1].text)'", kind: .lostWord)
                }
                let symbol = kept[index + 1].matching
                let spelling =
                    Self.closedSpelling(token.text) + (Self.symbolNames[symbol] ?? "")
                    + Self.closedSpelling(kept[index + 2].text)
                if let range = Self.matchingSymbolSpelling(spelling, in: written, startingAt: reached) {
                    reached = range.upperBound
                    index += 3
                    continue
                }
            }
            if token.matching.count == 1, token.matching.first?.isLetter == true {
                var end = index
                var acronym = ""
                while end < kept.count, kept[end].matching.count == 1,
                    kept[end].matching.first?.isLetter == true
                {
                    acronym += kept[end].matching
                    end += 1
                }
                if acronym.count > 1,
                    let place = written.indices.first(where: {
                        $0 >= reached && written[$0].matching == acronym
                    })
                {
                    reached = place + 1
                    index = end
                    continue
                }
            }
            let matchingPlaces = written.indices.filter {
                survives(
                    token.matching, as: written[$0],
                    allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
            }
            guard !matchingPlaces.isEmpty else {
                return .rejected(reason: "the rewrite lost or replaced '\(token.text)'", kind: .lostWord)
            }
            // The earliest place still open is taken, which is the most room the words after it can be left.
            guard let place = matchingPlaces.first(where: { $0 >= reached }) else {
                return .rejected(reason: "the rewrite moved '\(token.text)'", kind: .movedWord)
            }
            reached = place
            index += 1
        }
        return .accepted
    }

    /// Keeps three or more adjacent spoken letter names together so articles like "a" can start an acronym.
    static func isAcronymLetter(at index: Int, in tokens: [GrammarToken]) -> Bool {
        guard tokens[index].matching.count == 1, tokens[index].matching.first?.isLetter == true else {
            return false
        }
        var start = index
        while start > 0, tokens[start - 1].matching.count == 1,
            tokens[start - 1].matching.first?.isLetter == true
        {
            start -= 1
        }
        var end = index + 1
        while end < tokens.count, tokens[end].matching.count == 1,
            tokens[end].matching.first?.isLetter == true
        {
            end += 1
        }
        return end - start >= 3
    }

    /// Closes punctuation between adjacent spoken words when checking a symbol spelling.
    private static func closedSpelling(_ word: String) -> String {
        word.lowercased().filter(\.isLetter).description
    }

    /// Finds adjacent written tokens whose spelling includes the spoken symbol between its neighbours.
    private static func matchingSymbolSpelling(
        _ spelling: String, in written: [GrammarToken], startingAt start: Int
    ) -> Range<Int>? {
        guard !spelling.isEmpty else { return nil }
        for first in start..<written.count {
            var combined = ""
            for end in first..<written.count {
                combined += written[end].text.lowercased()
                if combined == spelling.lowercased() { return first..<(end + 1) }
                if combined.count >= spelling.count { break }
            }
        }
        return nil
    }

    /// Spoken punctuation names whose written marks join the words on either side.
    static let symbolNames: [String: String] = [
        "dot": ".", "period": ".", "underscore": "_", "slash": "/", "backslash": "\\",
        "at": "@", "hyphen": "-", "dash": "-", "plus": "+", "hash": "#",
    ]

    /// Maps every spelling accepted by `survives` to its token positions, preserving their original order.
    struct WordOccurrenceIndex {
        private let places: [String: [Int]]
        private let tokens: [GrammarToken]

        init(_ tokens: [GrammarToken]) {
            self.tokens = tokens
            var indexed: [String: [Int]] = [:]
            for (index, token) in tokens.enumerated() {
                var spellings: Set<String> = [token.matching]
                if let spoken = MeaningPreservationGuard.numberWordsByNumeral[token.matching] {
                    spellings.formUnion(spoken)
                }
                if let numeral = MeaningPreservationGuard.numberWords[token.matching] {
                    spellings.insert(numeral)
                }
                if let homophones = Homophones.group(containing: token.matching) {
                    spellings.formUnion(homophones)
                }
                if MeaningPreservationGuard.auxContractionRoots.contains(token.matching) {
                    spellings.insert("\(token.matching)nt")
                }
                if MeaningPreservationGuard.auxContractionRoots.contains(where: {
                    "\($0)nt" == token.matching
                }) {
                    spellings.insert(String(token.matching.dropLast(2)))
                }
                spellings.formUnion(Self.identifierSpellings(token.text))
                for spelling in spellings {
                    indexed[spelling, default: []].append(index)
                }
            }
            places = indexed
        }

        private static func identifierSpellings(_ identifier: String) -> Set<String> {
            let characters = Array(identifier)
            let lowered = Array(identifier.lowercased())
            guard lowered.count == characters.count else { return [] }
            var spellings: Set<String> = []
            for start in characters.indices {
                let opens = start == 0 || characters[start].isUppercase || !characters[start - 1].isLetter
                guard opens else { continue }
                for end in (start + 1)...characters.count {
                    let closes =
                        end == characters.count || characters[end].isUppercase || !characters[end].isLetter
                    if closes, end - start >= 3 {
                        spellings.insert(String(lowered[start..<end]))
                    }
                }
            }
            return spellings
        }

        func occurrences(of word: String) -> [Int] { places[word] ?? [] }

        func firstOccurrence(of word: String, atOrAfter lowerBound: Int) -> Int? {
            guard let candidates = places[word] else { return nil }
            var low = 0
            var high = candidates.count
            while low < high {
                let middle = (low + high) / 2
                if candidates[middle] < lowerBound { low = middle + 1 } else { high = middle }
            }
            return low < candidates.count ? candidates[low] : nil
        }

        func matchingOrigins(
            _ token: GrammarToken, allowingRomanisedHindiSpellings: Bool, excluding used: Set<Int>
        ) -> [Int]? {
            let exact = places[token.matching] ?? []
            if let match = exact.first(where: { !used.contains($0) }) { return [match] }

            // Preserve compound identifier matches, consuming each source word at most once.
            let parts = MeaningPreservationGuard.identifierParts(token.text)
            if parts.count > 1 {
                var next = 0
                var matched: [Int] = []
                for part in parts {
                    guard let place = firstOccurrence(of: part, atOrAfter: next), !used.contains(place)
                    else { matched.removeAll(); break }
                    matched.append(place)
                    next = place + 1
                }
                if !matched.isEmpty { return matched }
            }

            if let letters = spokenLetters(spelling: token.matching, excluding: used) { return letters }

            return tokens.indices.first { index in
                !used.contains(index)
                    && WordForms.sameForm(
                        tokens[index].matching, token.matching, allowingRegularInflections: false,
                        allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
            }.map { [$0] }
        }

        /// Finds the adjacent unused letter names spoken one per word that spell the written initialism letter for letter.
        private func spokenLetters(spelling initialism: String, excluding used: Set<Int>) -> [Int]? {
            let letters = initialism.map(String.init)
            guard letters.count > 1, initialism.allSatisfy(\.isLetter), tokens.count >= letters.count else {
                return nil
            }
            for start in 0...(tokens.count - letters.count) {
                let run = Array(start..<(start + letters.count))
                if zip(run, letters).allSatisfy({ !used.contains($0) && tokens[$0].matching == $1 }) {
                    return run
                }
            }
            return nil
        }

        func contains(_ word: String) -> Bool { places[word] != nil }

        func spells(_ identifier: String) -> Bool {
            let parts = MeaningPreservationGuard.identifierParts(identifier)
            guard parts.count > 1 else { return false }
            var next = 0
            for part in parts {
                guard let place = firstOccurrence(of: part, atOrAfter: next) else { return false }
                next = place + 1
            }
            return true
        }
    }

    /// Number spellings grouped by their numeral so occurrence indexes can add reverse matches in one lookup.
    private static let numberWordsByNumeral: [String: Set<String>] = numberWords.reduce(into: [:]) {
        index, entry in
        index[entry.value, default: []].insert(entry.key)
    }

    /// Whether a rewritten word preserves the kept word as a listed form, numeral, homophone, identifier spelling, or contracted auxiliary.
    static func survives(
        _ word: String, as candidate: GrammarToken, allowingRomanisedHindiSpellings: Bool = false
    ) -> Bool {
        if WordForms.sameForm(
            word, candidate.matching, allowingRegularInflections: false,
            allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
        {
            return true
        }
        if numberWords[word] == candidate.matching { return true }
        if numberWords[candidate.matching] == word { return true }
        // A misheard sound-alike respelled is the same spoken word, and only the hand-kept table says which are.
        if Homophones.share(word, candidate.matching) { return true }
        // A word spelled into an identifier — "invoices" inside "fetchInvoices" — is still there.
        if symbolNames[word] == nil, WordForms.spelledInto(word, candidate.text) { return true }
        // An auxiliary the rewrite contracted to its "n't" form is the same word.
        if Self.auxContractionRoots.contains(word), candidate.matching == "\(word)nt" { return true }
        if Self.auxContractionRoots.contains(candidate.matching), word == "\(candidate.matching)nt" {
            return true
        }
        return false
    }
}
