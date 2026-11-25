// The Dictionary page's "Recently learnt" list: its rows and the presenter step that builds them.
public import Foundation
internal import UttrflowDictionary

/// The short list above the words of what was learnt lately, so a wrong guess can be taken back.
public struct DictionaryRecentlyLearnt: Sendable, Equatable {
    /// "Recently learnt".
    public let title: String
    /// One word and its Undo, newest first.
    public let rows: [DictionaryLearntRow]

    /// Builds the list from its parts.
    public init(title: String, rows: [DictionaryLearntRow]) {
        self.title = title
        self.rows = rows
    }
}

/// One word learnt lately: what it replaces, where and when, and the Undo that removes and refuses it.
public struct DictionaryLearntRow: Sendable, Equatable, Identifiable {
    /// The dictionary entry's identifier.
    public let id: UUID
    public let word: String
    /// `heard “x”, wrote “Word”` for a correction, or where a word read off the screen came from.
    public let detail: String
    /// "Notes · today 10:12": the app, when it is known, and when.
    public let place: String
    /// Removes the word and refuses its spelling, as deleting it from the table does.
    public let undo: MainAction

    /// Builds a row from its parts.
    public init(id: UUID, word: String, detail: String, place: String, undo: MainAction) {
        self.id = id
        self.word = word
        self.detail = detail
        self.place = place
        self.undo = undo
    }
}

extension DictionaryPresenter {
    /// The words learnt lately that are still in the dictionary; a search shows only matches, so the list hides.
    static func recentlyLearnt(
        in snapshot: DictionarySnapshot, calendar: Calendar, locale: Locale
    ) -> DictionaryRecentlyLearnt? {
        guard snapshot.query.trimmingCharacters(in: .whitespaces).isEmpty, snapshot.draft == nil else {
            return nil
        }
        let spellings = Dictionary(
            snapshot.entries.map { ($0.id, $0.word) }, uniquingKeysWith: { first, _ in first })
        let rows = snapshot.learnt.compactMap { learnt -> DictionaryLearntRow? in
            guard let spelling = spellings[learnt.id] else { return nil }
            let word = LearnedWord(
                id: learnt.id, word: spelling, isFromScreen: learnt.isFromScreen,
                learnedAt: learnt.learnedAt, heard: learnt.heard, application: learnt.application)
            let when = MainFormatting.day(
                word.learnedAt, now: snapshot.now, calendar: calendar, locale: locale)
            let time =
                calendar.isDate(word.learnedAt, inSameDayAs: snapshot.now)
                ? " " + MainFormatting.time(word.learnedAt, locale: locale) : ""
            let place = [word.application, when + time].compactMap { $0 }.joined(separator: " · ")
            let detail =
                word.heard.map { "heard “\($0)”, wrote “\(word.word)”" } ?? "Read off the screen and said"
            return DictionaryLearntRow(
                id: word.id, word: word.word, detail: detail, place: place,
                undo: MainAction(
                    title: "Undo", symbolName: "arrow.uturn.backward", intent: .forgetWords([word.id])))
        }
        return rows.isEmpty ? nil : DictionaryRecentlyLearnt(title: "Recently learnt", rows: rows)
    }
}
