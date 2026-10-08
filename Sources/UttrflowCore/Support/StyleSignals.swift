// How a user writes in each kind of destination, kept as counts in the evidence ledger and never as text.

import Foundation

/// The style numbers for one destination, projected from evidence rows. See `Docs/learned-state.md`.
public struct StyleSignals: Sendable, Equatable {
    /// A dictation of at most this many words is a short one, where a closing stop is a choice of register.
    public static let shortMessageWords = 12

    /// Dictations measured.
    public let messages: Int
    /// Words across every measured dictation.
    public let words: Int
    /// Sentences across every measured dictation; a dictation with no closing mark counts as one.
    public let sentences: Int
    /// Dictations of at most ``shortMessageWords`` words.
    public let shortMessages: Int
    /// Short dictations that end with a full stop.
    public let closingStops: Int

    /// Words per sentence, or nil before any sentence is measured.
    public var meanSentenceLength: Double? {
        sentences > 0 ? Double(words) / Double(sentences) : nil
    }

    /// The share of short dictations ending with a full stop, or nil before any is measured.
    public var closingStopRate: Double? {
        shortMessages > 0 ? Double(closingStops) / Double(shortMessages) : nil
    }

    /// The rows one inserted dictation adds: counts keyed by destination, with no word of the text.
    public static func rows(
        for text: String, into destination: Destination, day: Int
    ) -> [EvidenceRow] {
        let wordCount = WordShape.words(text).count
        guard wordCount > 0 else { return [] }
        let subject = destination.rawValue
        func row(_ kind: EvidenceRow.Kind, _ weight: Int) -> EvidenceRow {
            EvidenceRow(kind: kind, subject: subject, weight: weight, day: day, provenance: .dictation)
        }
        var rows = [
            row(.styleMessage, 1), row(.styleWords, wordCount), row(.styleSentences, sentenceCount(text)),
        ]
        if wordCount <= shortMessageWords {
            rows.append(row(.styleShortMessage, 1))
            if endsWithStop(text) { rows.append(row(.styleClosingStop, 1)) }
        }
        return rows
    }

    /// Sums the style rows about one destination; rows of other kinds or destinations are ignored.
    public static func project(_ rows: [EvidenceRow], for destination: Destination) -> StyleSignals {
        var totals: [EvidenceRow.Kind: Int] = [:]
        for row in rows where row.subject == destination.rawValue {
            totals[row.kind, default: 0] += row.weight
        }
        return StyleSignals(
            messages: totals[.styleMessage] ?? 0, words: totals[.styleWords] ?? 0,
            sentences: totals[.styleSentences] ?? 0, shortMessages: totals[.styleShortMessage] ?? 0,
            closingStops: totals[.styleClosingStop] ?? 0)
    }

    /// Runs of text closed by a sentence mark followed by a space or the end, plus an unclosed tail.
    static func sentenceCount(_ text: String) -> Int {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var closed = 0
        var openWords = false
        for (index, character) in characters.enumerated() {
            if sentenceMarks.contains(character) {
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                if next.isWhitespace, openWords {
                    closed += 1
                    openWords = false
                }
            } else if character.isLetter || character.isNumber {
                openWords = true
            }
        }
        return closed + (openWords ? 1 : 0)
    }

    private static func endsWithStop(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last == "."
    }

    private static let sentenceMarks: Set<Character> = [".", "?", "!"]
}
