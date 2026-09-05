import Foundation
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// One plausible personal dictionary, and a notation for utterances that shows which words are doubted.
enum CorrectionFixtures {
    /// A real person's dictionary, stocked on purpose with words that collide with ordinary English.
    static let words = [
        "Uttrflow", "asyncpg", "Nikhil", "Naveen Bhatt", "PaymentSheet", "kubectl",
        "Postgres", "Claude", "Grafana", "Kestrel", "Redis", "Aditi", "setUserPrefs",
        "Valkey", "Sonnet", "Cassandra", "Terraform", "Maven", "SQL", "API", "XML",
        "CSS", "URL", "Kubernetes",
    ]

    /// The phonetic index over ``entries``.
    static let index = PhoneticIndex(entries: entries)

    /// The words as entries with one fixed date, so bucket order is the same every run.
    static let entries: [DictionaryEntry] = words.map {
        // A fixed date so the ordering inside a phonetic bucket is the same every run.
        DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
    }

    /// An utterance written as a sentence, where a leading `?` marks a word the recogniser doubted.
    static func spoken(_ text: String, unsure: Double = 0.2, sure: Double = 0.95) -> Utterance {
        Utterance(
            words: text.split(whereSeparator: \.isWhitespace).map {
                $0.hasPrefix("?")
                    ? SpokenWord(text: String($0.dropFirst()), confidence: unsure)
                    : SpokenWord(text: String($0), confidence: sure)
            })
    }

    /// An utterance with every word doubted: the worst hearing that still reports the right words.
    static func doubting(_ sentence: String) -> Utterance {
        spoken(sentence.split(whereSeparator: \.isWhitespace).map { "?\($0)" }.joined(separator: " "))
    }

    /// A screen showing this text as the frontmost document.
    static func showing(_ text: String) -> AppContext {
        AppContext(applicationName: "Code", documentName: text)
    }

    /// A screen showing every dictionary word at once, the most hostile context there is.
    static let showingEverything = showing(words.joined(separator: " "))
}
