// The words the dictionary learned lately, held in memory so the menu bar can offer each one back.

public import Foundation
public import UttrflowDictionary

/// One word the dictionary taught itself, with where the evidence came from.
public struct LearnedWord: Sendable, Equatable, Identifiable {
    /// The dictionary entry's identifier, which is what Undo removes.
    public let id: UUID
    public let word: String
    /// Read off the screen and said aloud, rather than taken from a correction.
    public let isFromScreen: Bool
    public let learnedAt: Date
    /// The text a correction replaces, when the word came from one; `nil` for a word read off the screen.
    public let heard: String?
    /// The app the dictation goes into, when it is known.
    public let application: String?

    public init(
        id: UUID, word: String, isFromScreen: Bool, learnedAt: Date, heard: String? = nil,
        application: String? = nil
    ) {
        self.id = id
        self.word = word
        self.isFromScreen = isFromScreen
        self.learnedAt = learnedAt
        self.heard = heard
        self.application = application
    }

    /// Where the word came from, in the words the popover row and VoiceOver both use.
    public var source: String { isFromScreen ? "from the screen" : "from a correction" }
}

/// Every word learned within ``holdingPeriod``, newest first; nothing here is written anywhere.
public struct RecentlyLearned: Sendable, Equatable {
    /// How long a learned word stays on offer for Undo.
    public static let holdingPeriod: TimeInterval = 24 * 60 * 60

    public private(set) var words: [LearnedWord] = []

    public init() {}

    /// Adds what one dictation taught, every inferred entry and not only the first, and answers with those.
    @discardableResult
    public mutating func record(
        _ entries: [DictionaryEntry], at moment: Date, heard: String? = nil, application: String? = nil
    ) -> [LearnedWord] {
        let trimmed = heard?.trimmingCharacters(in: .whitespacesAndNewlines)
        let heard = trimmed?.isEmpty == false ? trimmed : nil
        let learnt = entries.compactMap { entry -> LearnedWord? in
            switch entry.origin {
            case .learned:
                LearnedWord(
                    id: entry.id, word: entry.word, isFromScreen: false, learnedAt: moment, heard: heard,
                    application: application)
            case .observed:
                LearnedWord(
                    id: entry.id, word: entry.word, isFromScreen: true, learnedAt: moment,
                    application: application)
            case .added, .shipped:
                nil
            }
        }
        let ids = Set(learnt.map(\.id))
        words = learnt + current(at: moment).filter { !ids.contains($0.id) }
        return learnt
    }

    /// Drops a word once it has been undone, so its row goes with it.
    public mutating func forget(_ id: UUID) {
        words.removeAll { $0.id == id }
    }

    /// Puts words back after their Undo failed, newest first, so their rows return.
    public mutating func restore(_ restored: [LearnedWord]) {
        let ids = Set(restored.map(\.id))
        words = (restored + words.filter { !ids.contains($0.id) }).sorted { $0.learnedAt > $1.learnedAt }
    }

    /// The words still within ``holdingPeriod`` of `moment`, newest first.
    public func current(at moment: Date) -> [LearnedWord] {
        words.filter { moment.timeIntervalSince($0.learnedAt) < Self.holdingPeriod }
    }

    /// What VoiceOver says for one dictation's words: the first by name, the rest by count.
    public static func announcement(for learnt: [LearnedWord]) -> String? {
        guard let first = learnt.first else { return nil }
        let named = "Learned “\(first.word)” \(first.source)."
        let others = learnt.count - 1
        guard others > 0 else { return named }
        return "\(named) \(others) more \(others == 1 ? "word" : "words") in the menu bar."
    }
}
