// What a dictation may teach the dictionary, and the tally of sightings.

import UttrflowCore

/// What one dictation may teach the dictionary; the default is to learn nothing. See Docs/app-dictionary.md.
enum LearnableWords {
    /// How many separate days a term must be both on screen and spoken on before it is kept: three.
    static let sightingsBeforeLearning = 3

    /// The most words either side of a correction may have; longer is a rewrite, not a correction.
    static let maximumWordsInACorrection = PhoneticIndex.maximumWordsPerEntry

    // MARK: - Seen on screen

    /// The terms in the window title that were also spoken, judged by sound key and phoneme distance; never the selection or app name.
    static func seenAndSaid(
        heard: String, seeing context: AppContext,
        encoding encode: (String) -> WordSound = { WordSound(of: $0) }
    ) -> [String] {
        guard let title = context.documentName else { return [] }
        return seenAndSaid(heard: heard, reading: title, encoding: encode)
    }

    /// The terms in the title and in lines the user types in consented apps that the speech also says, each once.
    static func seenAndSaid(heard: String, seeing context: AppContext, typed lines: [String]) -> [String] {
        let titled = seenAndSaid(heard: heard, seeing: context)
        guard !lines.isEmpty else { return titled }
        var already = Set(titled.map { $0.lowercased() })
        let typed = seenAndSaid(heard: heard, reading: lines.joined(separator: " "))
        return titled + typed.filter { already.insert($0.lowercased()).inserted }
    }

    /// The terms in one piece of on-screen text that the speech also says, judged by sound key and phoneme distance.
    private static func seenAndSaid(
        heard: String, reading title: String,
        encoding encode: (String) -> WordSound = { WordSound(of: $0) }
    ) -> [String] {
        let said = Utterance(heard: heard, confidence: 1).spans(upTo: PhoneticIndex.maximumWordsPerEntry)
        guard !said.isEmpty else { return [] }

        // Each span encoded once, and only once a title term is worth comparing against them.
        var spoken: [(text: String, sound: WordSound)]?
        var found: [String] = []
        var already: Set<String> = []
        for written in words(in: title, atMost: WorkingSet.maximumWordsOnScreen)
        where GeneralVocabulary.isWorthLearning(stableTitleWord(written))
            && already.insert(stableTitleWord(written).lowercased()).inserted
        {
            let term = stableTitleWord(written)
            let sound = encode(term)
            let spans = spoken ?? said.map { (text: $0.text, sound: encode($0.text)) }
            spoken = spans
            guard
                spans.contains(where: {
                    isDistinctSpelling(term, from: $0.text, numbered: term != written)
                        && sound.sounds(like: $0.sound)
                        && ReadingRestraint.soundsNear(term, heard: $0.text)
                })
            else { continue }
            found.append(term)
        }
        return found
    }

    /// Removes a trailing numeric version so numbered files share one inferred spelling.
    private static func stableTitleWord(_ word: String) -> String {
        let letters = word.prefix { $0.isLetter }
        return letters.isEmpty ? word : String(letters)
    }

    /// Whether a title term is a distinct written form of a heard span, or an unknown term heard exactly as written.
    private static func isDistinctSpelling(_ term: String, from heard: String, numbered: Bool) -> Bool {
        let titleLetters = ReadingRestraint.closedUp(term).filter(\.isLetter)
        let spokenLetters = ReadingRestraint.closedUp(heard).filter(\.isLetter)
        guard !term.contains(where: \.isNumber) else { return false }
        let uppercase = term.filter(\.isLetter)
        guard !(uppercase.count <= 5 && uppercase.count >= 2 && uppercase.allSatisfy(\.isUppercase)) else {
            return false
        }
        guard titleLetters.lowercased() == spokenLetters.lowercased() else { return true }
        return isMarkedClosing(term, of: heard)
            || (!numbered && isUnknownTermSaidAsWritten(term, heard: heard))
    }

    /// Whether one heard word is spelt as the title writes a term no English model knows ("pgvector"), unlike "Inbox".
    private static func isUnknownTermSaidAsWritten(_ term: String, heard: String) -> Bool {
        guard heard.split(whereSeparator: { !$0.isLetter }).count == 1,
            !term.allSatisfy({ !$0.isLetter || $0.isUppercase })
        else { return false }
        return !LexicalClass.isKnownEnglishWord(term)
    }

    /// Whether case marks heard words as one closed-up name ("PaymentSheet", "PG vector"), unlike "localhost".
    private static func isMarkedClosing(_ term: String, of heard: String) -> Bool {
        let parts = heard.split { !$0.isLetter }
        guard parts.count > 1 else { return false }
        let titleMarks =
            term.dropFirst().contains(where: \.isUppercase) && term.contains(where: \.isLowercase)
        let heardMarks =
            parts.dropFirst().contains { $0.first?.isUppercase == true }
            || parts.contains { $0.count >= 2 && $0.allSatisfy(\.isUppercase) }
        return titleMarks || heardMarks
    }

    // MARK: - Corrected by the user

    /// The spelling a dictation over a selection corrects, if it corrects one. See Docs/app-dictionary.md.
    static func corrected(over selection: String?, wrote: String) -> String? {
        guard let selection else { return nil }
        // One word past the limit is all that needs counting; a long selection is refused anyway.
        let before = words(in: selection, atMost: maximumWordsInACorrection + 1)
        let after = words(in: wrote, atMost: maximumWordsInACorrection + 1)
        guard (1...maximumWordsInACorrection).contains(before.count),
            (1...maximumWordsInACorrection).contains(after.count),
            before.joined(separator: " ").lowercased() != after.joined(separator: " ").lowercased()
        else { return nil }

        let replacement = after.joined(separator: " ")
        let selected = before.joined(separator: " ")
        // A Devanagari side is read by its romanisation, so a correction is learnt across scripts too.
        let romanisedReplacement = Romaniser.romanised(replacement)
        let romanisedSelected = Romaniser.romanised(selected)
        guard
            isNearSpelling(
                romanisedReplacement, of: romanisedSelected, sameWordCount: before.count == after.count)
        else { return nil }
        // A known word is learnt only as the user's spelling of the listed Hindi word it replaced, word for word.
        let isPreference =
            before.count == after.count
            && zip(after, before).allSatisfy { GeneralVocabulary.isHindiSpellingPreference($0, over: $1) }
        guard isPreference || after.allSatisfy(GeneralVocabulary.isWorthLearning) else { return nil }
        return replacement
    }

    /// Whether a replacement is a respelling within half the longer spelling's edit distance; see Docs/app-dictionary.md.
    static func isNearSpelling(_ replacement: String, of selected: String, sameWordCount: Bool) -> Bool {
        func letters(_ text: String) -> [Character] {
            Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
        }
        let pairs: [([Character], [Character])] =
            sameWordCount
            ? zip(
                words(in: replacement, atMost: maximumWordsInACorrection),
                words(in: selected, atMost: maximumWordsInACorrection)
            )
            .map { (letters($0), letters($1)) }
            : [(letters(replacement), letters(selected))]
        let written = letters(replacement)
        guard written.contains(where: \.isLetter), written.allSatisfy({ $0.isASCII }) else { return false }
        // A homophone is a choice between ordinary words; a spelling that makes no sound is not a word.
        guard
            !zip(
                words(in: replacement, atMost: maximumWordsInACorrection),
                words(in: selected, atMost: maximumWordsInACorrection)
            )
            .contains(where: { PhonemeLexicon.shared.soundsSame($0, $1) }),
            !WordSound(of: replacement).isSilent
        else { return false }
        return pairs.allSatisfy { new, old in
            !new.isEmpty && editDistance(new, old) * 2 < max(new.count, old.count)
        }
    }

    /// Levenshtein distance over characters with unit costs.
    static func editDistance(_ first: [Character], _ second: [Character]) -> Int {
        var previous = Array(0...second.count)
        for (row, character) in first.enumerated() {
            var current = [row + 1]
            for (column, other) in second.enumerated() {
                current.append(
                    min(
                        previous[column + 1] + 1, current[column] + 1,
                        previous[column] + (character == other ? 0 : 1)))
            }
            previous = current
        }
        return previous[second.count]
    }

    // MARK: - Reading words out of a screen

    /// The words in a piece of text, split on anything that is neither a letter nor a digit, at most `limit` of them.
    static func words(in text: String, atMost limit: Int) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.prefix(limit).map(String.init)
    }
}

/// On which days each noticed but unlearnt term turned up, keyed by a hash so no term text is kept.
struct SightingLedger: Sendable {
    /// The most terms kept waiting at once, well above a day's vocabulary.
    static let maximumPending = 128
    /// The most refusals kept at once; past it the oldest refusal lapses and that word may be counted again.
    static let maximumRefused = 512

    /// The distinct days each pending term was seen and said on, by the term's hash.
    private var pending: [String: Set<Int>] = [:]
    /// The spelling behind each hash seen in this run, in memory only, for the learnt spelling and sound-alike refusals.
    private var spelt: [String: String] = [:]
    /// Turns a lowercased term into the key it is counted under; `nil` means it cannot be counted privately.
    private let digest: @Sendable (String) -> String?
    /// Words the user has deleted, which the store writes down so a relaunch still refuses them.
    private var refused: Set<String> = []
    /// The refused words oldest first, in the user's spelling, so the bound lapses the oldest refusal.
    private var refusalOrder: [String] = []

    /// Starts from earlier refusals, oldest first, and earlier `sighting` rows; `digest` is the key hash.
    init(
        refusing earlier: [String] = [], remembering rows: [EvidenceRow] = [],
        digest: @escaping @Sendable (String) -> String? = { $0 }
    ) {
        self.digest = digest
        var net: [String: [Int: Int]] = [:]
        for row in rows where row.kind == .sighting {
            net[row.subject, default: [:]][row.day, default: 0] += row.weight
        }
        for (subject, days) in net {
            let kept = Set(days.filter { $0.value > 0 }.keys)
            if !kept.isEmpty { pending[subject] = kept }
        }
        for word in earlier { _ = refuse(word) }
        _ = prune()
    }

    /// How many refusals the ledger holds now.
    var refusalCount: Int { refused.count }

    /// How many terms are waiting now.
    var pendingCount: Int { pending.count }

    /// The refused words oldest first, which is what the store writes down.
    var refusals: [String] { refusalOrder }

    /// Whether the user has explicitly refused to learn this spelling.
    func isRefused(_ word: String) -> Bool { refused.contains(word.lowercased()) }

    /// Refuses a spelling and drops it and its known sound-alikes from the tally, answering the rows that cancel them.
    mutating func refuse(_ word: String) -> [EvidenceRow] {
        let key = word.lowercased()
        let sound = WordSound(of: word)
        let dropped = pending.keys.filter { subject in
            if subject == digest(key) { return true }
            guard !sound.isSilent, let other = spelt[subject] else { return false }
            return sound.sounds(like: WordSound(of: other))
        }
        let rows = forgetting(dropped)
        if refused.insert(key).inserted {
            refusalOrder.append(word)
            if refusalOrder.count > Self.maximumRefused {
                refused.remove(refusalOrder.removeFirst().lowercased())
            }
        }
        return rows
    }

    /// Lifts the refusal of this spelling so it may be counted again, answering whether it is refused.
    mutating func allow(_ word: String) -> Bool {
        let key = word.lowercased()
        guard refused.remove(key) != nil else { return false }
        refusalOrder.removeAll { $0.lowercased() == key }
        return true
    }

    /// Counts one dictation's sightings on `day`, answering the terms now seen on enough days and the rows to append.
    mutating func record(_ terms: [String], on day: Int) -> (learnt: [String], rows: [EvidenceRow]) {
        var learnt: [String] = []
        var rows: [EvidenceRow] = []
        for term in terms {
            let key = term.lowercased()
            guard !refused.contains(key), let subject = digest(key) else { continue }
            // The spelling first seen this run wins, so a term counted three times comes out spelt one way.
            let spelling = spelt[subject] ?? term
            spelt[subject] = spelling
            guard pending[subject, default: []].insert(day).inserted else { continue }
            rows.append(EvidenceRow(kind: .sighting, subject: subject, day: day, provenance: .dictation))
            if pending[subject, default: []].count >= LearnableWords.sightingsBeforeLearning {
                rows += forget(subject)
                learnt.append(spelling)
            }
        }
        rows += prune()
        return (learnt, rows)
    }

    /// Drops every pending term, keeping refusals, answering the rows that cancel them.
    mutating func clearPending() -> [EvidenceRow] {
        forgetting(Array(pending.keys))
    }

    /// Throws the tally and the refusals away, answering the rows that cancel the tally.
    mutating func forgetEverything() -> [EvidenceRow] {
        refused.removeAll()
        refusalOrder.removeAll()
        return clearPending()
    }

    /// Removes each pending term, answering the cancelling rows of all of them.
    private mutating func forgetting(_ subjects: [String]) -> [EvidenceRow] {
        var rows: [EvidenceRow] = []
        for subject in subjects { rows += forget(subject) }
        return rows
    }

    /// Removes one pending term, answering a cancelling row for each day it held.
    private mutating func forget(_ subject: String) -> [EvidenceRow] {
        let days = pending.removeValue(forKey: subject) ?? []
        spelt[subject] = nil
        return days.sorted().map {
            EvidenceRow(kind: .sighting, subject: subject, weight: -1, day: $0, provenance: .dictation)
        }
    }

    /// Drops the weakest evidence when the tally outgrows its bound: fewest days, then oldest, then by key.
    private mutating func prune() -> [EvidenceRow] {
        guard pending.count > Self.maximumPending else { return [] }
        let ranked = pending.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            let (newest, other) = ($0.value.max() ?? 0, $1.value.max() ?? 0)
            return newest != other ? newest > other : $0.key < $1.key
        }
        return forgetting(ranked.dropFirst(Self.maximumPending).map(\.key))
    }
}
