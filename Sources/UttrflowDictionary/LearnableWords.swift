// What a dictation may teach the dictionary, and the tally of sightings.

import UttrflowCore

/// What one dictation may teach the dictionary; the default is to learn nothing. See Docs/app-dictionary.md.
enum LearnableWords {
    /// How many separate dictations a term must be both on screen and spoken in before it is kept: three.
    static let sightingsBeforeLearning = 3

    /// The most words either side of a correction may have; longer is a rewrite, not a correction.
    static let maximumWordsInACorrection = PhoneticIndex.maximumWordsPerEntry

    // MARK: - Seen on screen

    /// The terms in the window title that were also spoken, judged by sound; never the selection or app name.
    static func seenAndSaid(heard: String, seeing context: AppContext) -> [String] {
        guard let title = context.documentName else { return [] }
        let said = Utterance(heard: heard, confidence: 1)
            .sounds(upTo: PhoneticIndex.maximumWordsPerEntry)
        guard !said.isEmpty else { return [] }

        var found: [String] = []
        var already: Set<String> = []
        for term in words(in: title, atMost: WorkingSet.maximumWordsOnScreen)
        where GeneralVocabulary.isWorthLearning(term) && already.insert(term.lowercased()).inserted {
            guard DoubleMetaphone.code(for: term).sounds(likeAnyOf: said) else { continue }
            found.append(term)
        }
        return found
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
        let sound = DoubleMetaphone.code(for: replacement)
        guard !sound.isSilent,
            sound.sounds(like: DoubleMetaphone.code(for: before.joined(separator: " ")))
        else { return nil }
        guard after.allSatisfy(GeneralVocabulary.isWorthLearning) else { return nil }
        return replacement
    }

    // MARK: - Reading words out of a screen

    /// The words in a piece of text, split on anything that is not a letter, at most `limit` of them.
    static func words(in text: String, atMost limit: Int) -> [String] {
        text.split { !$0.isLetter }.prefix(limit).map(String.init)
    }
}

/// How often each noticed but unlearnt term has turned up; in memory only, never on disk.
struct SightingLedger: Sendable {
    /// The most terms kept waiting at once, well above a day's vocabulary.
    static let maximumPending = 128

    private struct Sighting: Sendable {
        /// The spelling first seen, kept so a term counted three times comes out spelt one way.
        let word: String
        var count: Int
    }

    private var sightings: [String: Sighting] = [:]
    /// Words the user has deleted since Uttrflow started, refused for the rest of the run.
    private var refused: Set<String> = []

    /// Stops counting a word and stops it being counted again; what a deletion reaches.
    mutating func refuse(_ word: String) {
        let key = word.lowercased()
        sightings[key] = nil
        refused.insert(key)
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
