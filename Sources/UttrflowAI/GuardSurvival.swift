import Foundation
import UttrflowCore
import UttrflowDictionary

// The guard's survival and word-order checks and the word-occurrence index they share.
extension MeaningPreservationGuard {
    /// Refuses a word the model moved, using the shared word alignment while leaving edits to the other guard checks.
    static func wordOrderVerdict(
        kept: [GrammarToken], written: [GrammarToken], allowingFormRepairs: Bool = false
    ) -> GuardVerdict {
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
                // A word repaired to another form of itself stands where it stood.
                if allowingFormRepairs, WordForms.sameForm(reference, hypothesis) { continue }
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
        _ kept: [GrammarToken], in written: [GrammarToken], allowingRomanisedHindiSpellings: Bool = false,
        allowingFormRepairs: Bool = false
    ) -> GuardVerdict {
        var reached = 0
        var index = 0
        while index < kept.count {
            let token = kept[index]
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
                    allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings,
                    allowingFormRepairs: allowingFormRepairs)
            }
            let nearest = matchingPlaces.first(where: { $0 >= reached })
            // Words written as one identifier, or a joined acronym written apart, count only where nothing nearer stands for the word.
            if let (end, place) = spelledIdentifier(from: index, of: kept, in: written, from: reached),
                nearest.map({ place <= $0 }) ?? true
            {
                reached = place
                index = end
                continue
            }
            if nearest == nil, let place = splitAcronym(token, in: written, from: reached) {
                reached = place
                index += 1
                continue
            }
            guard !matchingPlaces.isEmpty else {
                return .rejected(reason: "the rewrite lost or replaced '\(token.text)'", kind: .lostWord)
            }
            // The earliest place still open is taken, which is the most room the words after it can be left.
            guard let place = matchingPlaces.first(where: { $0 >= reached }) else {
                // A word said more often than the rewrite writes it was lost, not moved: a truncated answer.
                let said = kept[...index].filter { $0.matching == token.matching }.count
                if said > matchingPlaces.count {
                    return .rejected(reason: "the rewrite lost or replaced '\(token.text)'", kind: .lostWord)
                }
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

    /// The kept symbol names the rewrite writes as their marks, and the list prefixes whose label opens a line; the words beside them are still checked.
    static func writtenAsMarks(
        _ kept: [GrammarToken], saying spoken: String, in rewritten: String
    ) -> Set<Int> {
        let text = withoutThousandsSeparators(rewritten)
        var written = NotationAlignment.align(spoken: spoken, written: rewritten).writtenNames(in: kept)
        written.formUnion(unitsWrittenAsSymbols(kept, in: text))
        for index in kept.indices {
            let word = kept[index].matching
            if listPrefixes.contains(word), index + 1 < kept.count {
                // "item a" written as the label "(a)" opening a line.
                let label = escaped(kept[index + 1].matching)
                if matches("(?:^|\\n)[ \\t]*(?:[(\\[]\(label)[)\\]]|\(label)[.)])", in: text) {
                    written.insert(index)
                }
            } else if let place = NumberFormsPass.ordinalUnits[word], index + 1 < kept.count,
                opensListItem(place, on: spellings(of: kept[index + 1]), in: text)
            {
                // "first book the hall" written as the item "1. Book the hall" or "- Book the hall": the sequence word goes.
                written.insert(index)
            }
        }
        return written
    }

    /// The kept currency and percent words the rewrite writes as the symbol beside the same amount: "12 dollars" as `$12`, "8 percent" as `8%`.
    static func unitsWrittenAsSymbols(_ kept: [GrammarToken], in rewritten: String) -> Set<Int> {
        var starts: [Int] = []
        var said = ""
        for token in kept {
            if !said.isEmpty { said += " " }
            starts.append(said.count)
            said += token.text
        }
        let characters = Array(said)
        // Only a mark the rewrite wrote counts, each one crediting a single amount said with its unit word.
        var marked = Quantities.read(in: rewritten).filter { !$0.symbol.isEmpty }
        var written: Set<Int> = []
        for span in Quantities.spans(in: said) where span.quantity.symbol.isEmpty {
            let symbol = Quantities.symbolNamed(after: characters, at: span.range.upperBound)
            guard !symbol.isEmpty, let unit = starts.firstIndex(of: span.range.upperBound + 1),
                let place = marked.firstIndex(where: {
                    $0.digits == span.quantity.digits && $0.symbol == symbol
                })
            else { continue }
            marked.remove(at: place)
            // "per cent" is two kept words for the one mark.
            let length = kept[unit].matching == "per" ? 2 : 1
            written.formUnion(unit..<min(unit + length, kept.count))
        }
        return written
    }

    /// Whether a line opens a list item numbered `place`, or bulleted unless only a number will do, on the word pattern given.
    static func opensListItem(
        _ place: Int, on word: String = "", bulleted: Bool = true, in text: String
    ) -> Bool {
        let marker = bulleted ? "(?:\(place)[.)]|[-*\u{2022}])" : "\(place)[.)]"
        return matches(
            "(?:^|\\n)[ \\t]*" + marker + "[ \\t]+" + word + (word.isEmpty ? "" : closing), in: text)
    }

    /// A neighbouring word as a pattern, a number word also matching its numeral.
    private static func spellings(of token: GrammarToken) -> String {
        let forms = [token.matching] + (numberWords[token.matching].map { [$0] } ?? [])
        return "(?:" + forms.map(escaped).joined(separator: "|") + ")"
    }

    private static let closing = "(?![\\p{L}\\p{N}])"

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The written place where an all-capital kept token stands split into its parts: "APR" as "a PR".
    private static func splitAcronym(
        _ token: GrammarToken, in written: [GrammarToken], from reached: Int
    ) -> Int? {
        guard token.text.count > 1, !token.text.contains(where: \.isLowercase) else { return nil }
        for start in written.indices where start >= reached {
            var spelled = ""
            for end in start..<written.count {
                spelled += written[end].matching
                if spelled == token.matching, end > start { return start }
                if !token.matching.hasPrefix(spelled) { break }
            }
        }
        return nil
    }

    /// The kept words a written identifier is spelled from, part for part and in order: "user id" as `user_id`, "mac os" as `macOS`.
    private static func spelledIdentifier(
        from start: Int, of kept: [GrammarToken], in written: [GrammarToken], from reached: Int
    ) -> (end: Int, place: Int)? {
        for place in written.indices where place >= reached {
            let parts = identifierParts(written[place].text)
            let end = start + parts.count
            guard parts.count > 1, end <= kept.count else { continue }
            // A symbol's name spelled into the identifier is the name left in, not its mark.
            if kept[start..<end].map(\.matching) == parts, !parts.contains(where: symbolNameWords.contains) {
                return (end, place)
            }
        }
        return nil
    }

    private static func escaped(_ literal: String) -> String {
        NSRegularExpression.escapedPattern(for: literal)
    }

    /// Words that may stand before the label of a list item, as in "number one" and "item a".
    public static let listPrefixes: Set<String> = ["number", "point", "item", "step"]

    /// Every one-word spoken symbol name, from the shared code and flag rows and the joining names.
    static let symbolNameWords: Set<String> = Set(symbolNames.keys).union(
        // Prose marks said by name are judged by where the spoken-punctuation pass would put them, not here.
        (SpokenCommands.codeSymbols + SpokenCommands.flags).filter { $0.words.count == 1 }.map { $0.words[0] }
    )

    /// Spoken punctuation names whose written marks join the words on either side.
    static let symbolNames: [String: String] = [
        "dot": ".", "period": ".", "underscore": "_", "slash": "/", "backslash": "\\",
        "at": "@", "hyphen": "-", "dash": "-", "plus": "+", "hash": "#", "backtick": "`",
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
                if let numeral = MeaningPreservationGuard.ordinalNumerals[token.matching] {
                    spellings.insert(numeral)
                }
                spellings.formUnion(GeneralVocabulary.soundAlikes(of: token.matching))
                spellings.formUnion(MeaningPreservationGuard.meridiemSpellings(of: token.matching))
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
            _ token: GrammarToken, allowingRomanisedHindiSpellings: Bool, allowingFormRepairs: Bool = false,
            excluding used: Set<Int>
        ) -> [Int]? {
            let exact = places[token.matching] ?? []
            if let match = exact.first(where: { !used.contains($0) }) { return [match] }

            // Compound identifiers, and a numeral run into a letter such as `3x`, consume each source word at most once.
            let identifier = MeaningPreservationGuard.identifierParts(token.text)
            let parts =
                identifier.count > 1 ? identifier : MeaningPreservationGuard.alphanumericRuns(token.text)
            if parts.count > 1 {
                var next = 0
                var matched: [Int] = []
                for part in parts {
                    // The first occurrence still unused, so an identifier written twice takes the words said twice.
                    guard
                        let place = occurrences(of: part).first(where: { $0 >= next && !used.contains($0) })
                    else { matched.removeAll(); break }
                    matched.append(place)
                    next = place + 1
                }
                if !matched.isEmpty { return matched }
            }

            if let letters = spokenLetters(spelling: token.matching, excluding: used) { return letters }

            // Letters a pass ran together as one capital token — "APR" for "a p r" — may be written apart again: "a PR", `CI/CD`.
            if token.text.count > 1, !token.text.contains(where: \.isLowercase),
                let joined = tokens.indices.first(where: { index in
                    (!used.contains(index) || tokens[index].matching.hasSuffix(token.matching))
                        && tokens[index].text.count > token.text.count
                        && !tokens[index].text.contains(where: \.isLowercase)
                        && (tokens[index].matching.hasPrefix(token.matching)
                            || tokens[index].matching.hasSuffix(token.matching))
                })
            {
                return [joined]
            }

            return tokens.indices.first { index in
                !used.contains(index)
                    && WordForms.sameForm(
                        tokens[index].matching, token.matching,
                        allowingRegularInflections: allowingFormRepairs,
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

    /// A token cut where letters meet digits: `3x` as "3" and "x".
    static func alphanumericRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var previous: Character?
        for character in text.lowercased() where character.isLetter || character.isNumber {
            if let previous, previous.isNumber == character.isNumber, !runs.isEmpty {
                runs[runs.count - 1].append(character)
            } else {
                runs.append(String(character))
            }
            previous = character
        }
        return runs
    }

    /// A meridiem's other spellings, plain and dotted, so "pm" and `p.m.` are one word; empty for any other word.
    static func meridiemSpellings(of word: String) -> Set<String> {
        guard NumberFormsPass.meridiems.contains(word) else { return [] }
        let plain = word.filter { $0 != "." }
        return NumberFormsPass.meridiems.filter { $0.filter { $0 != "." } == plain }
    }

    /// Number spellings grouped by their numeral so occurrence indexes can add reverse matches in one lookup.
    private static let numberWordsByNumeral: [String: Set<String>] = numberWords.reduce(into: [:]) {
        index, entry in
        index[entry.value, default: []].insert(entry.key)
    }

    /// Whether a rewritten word preserves the kept word as a listed form, numeral, homophone, identifier spelling, or contracted auxiliary.
    static func survives(
        _ word: String, as candidate: GrammarToken, allowingRomanisedHindiSpellings: Bool = false,
        allowingFormRepairs: Bool = false
    ) -> Bool {
        if WordForms.sameForm(
            word, candidate.matching, allowingRegularInflections: allowingFormRepairs,
            allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
        {
            return true
        }
        if numberWords[word] == candidate.matching { return true }
        if numberWords[candidate.matching] == word { return true }
        if meridiemSpellings(of: word).contains(candidate.matching) { return true }
        if ordinalNumerals[word] == candidate.matching { return true }
        // A misheard sound-alike respelled is the same spoken word: the lexicon lists one pronunciation for both.
        if GeneralVocabulary.soundAlikes(of: word).contains(candidate.matching) { return true }
        // A word spelled into an identifier — "invoices" inside "fetchInvoices" — is still there.
        if symbolNames[word] == nil, WordForms.spelledInto(word, candidate.text) { return true }
        // A numeral run into a unit or a letter — "3" in `3x` — is the number said.
        let runs = alphanumericRuns(candidate.text)
        if runs.count > 1, runs.contains(word) || numberWords[word].map(runs.contains) == true { return true }
        // A word joined to others by marks — "20" in `node:20`, "go" in `main.go` — is still there.
        if symbolNames[word] == nil, identifierParts(candidate.text).count > 1,
            identifierParts(candidate.text).contains(word)
        {
            return true
        }
        // An auxiliary the rewrite contracted to its "n't" form is the same word.
        if Self.auxContractionRoots.contains(word), candidate.matching == "\(word)nt" { return true }
        if Self.auxContractionRoots.contains(candidate.matching), word == "\(candidate.matching)nt" {
            return true
        }
        return false
    }
}
