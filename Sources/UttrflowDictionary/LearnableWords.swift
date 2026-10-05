// What a dictation may teach the dictionary, and the tally of sightings.

import UttrflowCore

/// What one dictation may teach the dictionary; the default is to learn nothing. See Docs/app-dictionary.md.
enum LearnableWords {
    /// How many separate dictations a term must be both on screen and spoken in before it is kept: three.
    static let sightingsBeforeLearning = 3

    /// The most words either side of a correction may have; longer is a rewrite, not a correction.
    static let maximumWordsInACorrection = PhoneticIndex.maximumWordsPerEntry

    // MARK: - Seen on screen

    /// The terms in the window title that were also spoken, judged by sound and opening; never the selection or app name.
    static func seenAndSaid(
        heard: String, seeing context: AppContext,
        encoding encode: (String) -> PhoneticCode = DoubleMetaphone.code(for:)
    ) -> [String] {
        guard let title = context.documentName else { return [] }
        let said = Utterance(heard: heard, confidence: 1).spans(upTo: PhoneticIndex.maximumWordsPerEntry)
        guard !said.isEmpty else { return [] }

        // Each span encoded once, and only once a title term is worth comparing against them.
        var spoken: [(text: String, sound: PhoneticCode)]?
        var found: [String] = []
        var already: Set<String> = []
        for term in words(in: title, atMost: WorkingSet.maximumWordsOnScreen)
            .map(stableTitleWord)
        where GeneralVocabulary.isWorthLearning(term) && already.insert(term.lowercased()).inserted {
            let sound = encode(term)
            let spans = spoken ?? said.map { (text: $0.text, sound: encode($0.text)) }
            spoken = spans
            guard
                spans.contains(where: {
                    isDistinctSpelling(term, from: $0.text)
                        && sound.sounds(like: $0.sound)
                        && ReadingRestraint.opensAlike(term, heard: $0.text)
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

    /// Whether a title term is a distinct written form of a heard span, not an identical word or abbreviation.
    private static func isDistinctSpelling(_ term: String, from heard: String) -> Bool {
        let titleLetters = ReadingRestraint.closedUp(term).filter(\.isLetter)
        let spokenLetters = ReadingRestraint.closedUp(heard).filter(\.isLetter)
        guard !term.contains(where: \.isNumber) else { return false }
        let uppercase = term.filter(\.isLetter)
        guard !(uppercase.count <= 5 && uppercase.count >= 2 && uppercase.allSatisfy(\.isUppercase)) else {
            return false
        }
        guard titleLetters.lowercased() != spokenLetters.lowercased() else { return false }
        return true
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
        let sound = DoubleMetaphone.code(for: romanisedReplacement)
        guard !sound.isSilent,
            sound.sounds(like: DoubleMetaphone.code(for: romanisedSelected)),
            ReadingRestraint.opensAlike(romanisedReplacement, heard: romanisedSelected)
        else { return nil }
        // A known word is learnt only as the user's spelling of the listed Hindi word it replaced, word for word.
        let isPreference =
            before.count == after.count
            && zip(after, before).allSatisfy { GeneralVocabulary.isHindiSpellingPreference($0, over: $1) }
        guard isPreference || after.allSatisfy(GeneralVocabulary.isWorthLearning) else { return nil }
        return replacement
    }

    // MARK: - Reading words out of a screen

    /// The words in a piece of text, split on anything that is neither a letter nor a digit, at most `limit` of them.
    static func words(in text: String, atMost limit: Int) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.prefix(limit).map(String.init)
    }
}

/// How often each noticed but unlearnt term has turned up; in memory only, never on disk.
struct SightingLedger: Sendable {
    /// The most terms kept waiting at once, well above a day's vocabulary.
    static let maximumPending = 128
    /// The most refusals kept at once; past it the oldest refusal lapses and that word may be counted again.
    static let maximumRefused = 512

    private struct Sighting: Sendable {
        /// The spelling first seen, kept so a term counted three times comes out spelt one way.
        let word: String
        var count: Int
    }

    private var sightings: [String: Sighting] = [:]
    /// Words the user has deleted, which the store writes down so a relaunch still refuses them.
    private var refused: Set<String> = []
    /// The refused words oldest first, in the user's spelling, so the bound lapses the oldest refusal.
    private var refusalOrder: [String] = []

    /// Starts with the refusals a previous run wrote down, oldest first, keeping only the newest the bound allows.
    init(refusing earlier: [String] = []) {
        for word in earlier { refuse(word) }
    }

    /// How many refusals the ledger holds now.
    var refusalCount: Int { refused.count }

    /// The refused words oldest first, which is what the store writes down.
    var refusals: [String] { refusalOrder }

    /// Whether the user has explicitly refused to learn this spelling.
    func isRefused(_ word: String) -> Bool { refused.contains(word.lowercased()) }

    /// Stops counting pending homophones and stops the refused spelling being counted again.
    mutating func refuse(_ word: String) {
        let key = word.lowercased()
        let sound = DoubleMetaphone.code(for: word)
        sightings = sightings.filter { sightingKey, sighting in
            guard sightingKey != key else { return false }
            guard !sound.isSilent else { return true }
            return !sound.sounds(like: DoubleMetaphone.code(for: sighting.word))
        }
        guard refused.insert(key).inserted else { return }
        refusalOrder.append(word)
        if refusalOrder.count > Self.maximumRefused {
            refused.remove(refusalOrder.removeFirst().lowercased())
        }
    }

    /// Lifts the refusal of this spelling so it may be counted again, answering whether it is refused.
    mutating func allow(_ word: String) -> Bool {
        let key = word.lowercased()
        guard refused.remove(key) != nil else { return false }
        refusalOrder.removeAll { $0.lowercased() == key }
        return true
    }

    /// Counts one dictation's sightings and returns the terms now seen and said often enough to keep.
    mutating func record(_ terms: [String]) -> [String] {
        var learnt: [String] = []
        for term in terms {
            let key = term.lowercased()
            guard !refused.contains(key) else { continue }
            var sighting = sightings[key] ?? Sighting(word: term, count: 0)
            sighting.count += 1
            if sighting.count >= LearnableWords.sightingsBeforeLearning {
                sightings[key] = nil
                learnt.append(sighting.word)
            } else {
                sightings[key] = sighting
            }
        }
        prune()
        return learnt
    }

    /// Throws the tally and the refusals away, so a reset leaves no half-counted evidence behind.
    mutating func forgetEverything() {
        sightings.removeAll()
        refused.removeAll()
        refusalOrder.removeAll()
    }

    /// Drops the weakest evidence when the tally outgrows its bound, deterministically.
    private mutating func prune() {
        guard sightings.count > Self.maximumPending else { return }
        let kept = sightings.sorted {
            $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key
        }
        sightings = Dictionary(
            uniqueKeysWithValues: kept.prefix(Self.maximumPending).map { ($0.key, $0.value) })
    }
}
