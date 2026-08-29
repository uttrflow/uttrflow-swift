import Foundation
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// The shared world these tests argue about: one plausible personal dictionary, and a way
/// to write an utterance down that shows at a glance which words the recogniser doubted.
enum CorrectionFixtures {
    /// A dictionary belonging to somebody real — the names they say and the tools they
    /// work in. Deliberately stocked with words that collide with ordinary English
    /// ("Claude", "Sonnet", "Kestrel", "Maven"), because those collisions are the whole
    /// hazard and a fixture that avoided them would test nothing.
    static let words = [
        "Uttrflow", "asyncpg", "Nikhil", "Naveen Bhatt", "PaymentSheet", "kubectl",
        "Postgres", "Claude", "Grafana", "Kestrel", "Redis", "Aditi", "setUserPrefs",
        "Valkey", "Sonnet", "Cassandra", "Terraform", "Maven", "SQL", "API", "XML",
        "CSS", "URL", "Kubernetes",
    ]

    static let index = PhoneticIndex(entries: entries)

    static let entries: [DictionaryEntry] = words.map {
        // A fixed date so the ordering inside a phonetic bucket is the same every run.
        DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
    }

    /// An utterance written as a sentence, where a leading `?` marks a word the recogniser
    /// was unsure of.
    ///
    /// Worth the small piece of notation: the three conditions turn on which words were
    /// doubted, and a test that expressed that as a parallel array of numbers would hide
    /// the one thing the reader needs to see.
    static func spoken(_ text: String, unsure: Double = 0.2, sure: Double = 0.95) -> Utterance {
        Utterance(
            words: text.split(whereSeparator: \.isWhitespace).map {
                $0.hasPrefix("?")
                    ? SpokenWord(text: String($0.dropFirst()), confidence: unsure)
                    : SpokenWord(text: String($0), confidence: sure)
            })
    }

    /// An utterance in which the recogniser was unsure of every single word — the worst
    /// hearing it could plausibly report while still reporting the right words.
    static func doubting(_ sentence: String) -> Utterance {
        spoken(sentence.split(whereSeparator: \.isWhitespace).map { "?\($0)" }.joined(separator: " "))
    }

    /// A screen showing this text as the frontmost document.
    static func showing(_ text: String) -> AppContext {
        AppContext(applicationName: "Code", documentName: text)
    }

    /// A screen showing every word in the dictionary at once.
    ///
    /// The most hostile context there is: it hands the on-screen signal to every candidate
    /// the index can produce, so anything that survives it survived on the strength of the
    /// other signals rather than on an empty context.
    static let showingEverything = showing(words.joined(separator: " "))
}
