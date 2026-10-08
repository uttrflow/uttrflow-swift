// A plain list of the words a person added, for sharing terms with a team.

public import Foundation
public import UttrflowCore
public import UttrflowDictionary

/// UTF-8 text, one word per line, optionally `word = say it like`; it holds no identifier, date or counter. See `Docs/personal-data-archive.md`.
public struct PersonalWordList: Sendable, Equatable {
    public static let maximumLineCount = 5_000
    public static let maximumLineLength = 64
    /// What separates a spelling from its pronunciations, which follow as the editor's comma-separated field.
    public static let pronunciationMark: Character = "="

    /// One line that holds text, numbered as the file numbers it.
    public struct Line: Sendable, Equatable {
        public let number: Int
        public let text: String
    }

    /// Every line holding text, blank lines left out of the list but not out of the numbering.
    public let lines: [Line]

    /// Reads the whole file, refusing one that is not UTF-8 text or holds more lines than the limit, before any store changes.
    public init(decoding data: Data) throws(PersonalWordListError) {
        guard var text = String(validating: data, as: UTF8.self)?[...] else { throw .notText }
        if text.first == "\u{FEFF}" { text = text.dropFirst() }
        var lines: [Line] = []
        var number = 0
        while true {
            number += 1
            let end = text.firstIndex(where: \.isNewline) ?? text.endIndex
            let line = text[..<end].trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                guard lines.count < Self.maximumLineCount else {
                    throw .tooManyLines(maximum: Self.maximumLineCount)
                }
                lines.append(Line(number: number, text: line))
            }
            guard end < text.endIndex else { break }
            text = text[text.index(after: end)...]
        }
        self.lines = lines
    }

    /// The words the person added, one line each in the order they were added; learned, seen and shipped words stay out.
    public static func encoded(_ entries: [DictionaryEntry]) -> Data {
        Data(entries.filter { $0.origin == .added }.map { line(for: $0) + "\n" }.joined().utf8)
    }

    /// One entry as a line: its spelling, then the mark and its pronunciations when it has any.
    static func line(for entry: DictionaryEntry) -> String {
        guard !entry.pronunciations.isEmpty else { return entry.word }
        return "\(entry.word) \(pronunciationMark) \(entry.pronunciationField)"
    }

    /// What importing over `existing` adds and skips, line by line, by the editor's own rules; nothing is written.
    public func plan(over existing: [DictionaryEntry], importedAt: Date) -> PersonalWordListReport {
        var spellings = Set(existing.map(\.spellingKey))
        var added: [DictionaryEntry] = []
        var skipped: [PersonalWordListReport.Skip] = []
        for line in lines {
            switch Self.entry(from: line.text, importedAt: importedAt) {
            case .failure(let problem):
                skipped.append(.init(line: line.number, problem: problem))
            case .success(let entry):
                guard spellings.insert(entry.spellingKey).inserted else {
                    skipped.append(.init(line: line.number, problem: .duplicate))
                    continue
                }
                added.append(entry)
            }
        }
        return PersonalWordListReport(added: added, skipped: skipped)
    }

    /// A line as a new word with zero counters, or the reason it cannot be one.
    private static func entry(
        from line: String, importedAt: Date
    ) -> Result<DictionaryEntry, PersonalWordListReport.Problem> {
        guard line.count <= maximumLineLength else { return .failure(.tooLong) }
        guard !PersonalDataArchive.holdsHiddenCharacters(line) else { return .failure(.hiddenCharacter) }
        let parts = line.split(separator: pronunciationMark, maxSplits: 1, omittingEmptySubsequences: false)
        let entry: DictionaryEntry
        do {
            entry = try PersonalDictionaryStore.typedEntry(
                word: String(parts[0]), pronunciation: parts.count > 1 ? String(parts[1]) : "",
                at: importedAt)
        } catch {
            return .failure(.refused(error))
        }
        // The spelling is what dictation writes; Devanagari is romanised above, any other script is refused.
        guard LatinScript.writesOnlyLatin(entry.word) else { return .failure(.notLatin) }
        return .success(entry)
    }
}

/// What a word-list import added, and each line it skipped with the reason.
public struct PersonalWordListReport: Sendable, Equatable {
    /// Why one line was not imported.
    public enum Problem: Error, Sendable, Equatable {
        /// The spelling is already in the dictionary or earlier in the file; the existing word is kept.
        case duplicate
        /// The line is longer than `PersonalWordList.maximumLineLength` characters.
        case tooLong
        /// The line holds a control or bidirectional formatting character, which can hide what it reads as.
        case hiddenCharacter
        /// The spelling holds letters of a script other than Latin or Devanagari.
        case notLatin
        /// The editor would refuse it: no spelling, too many words, or too long for the recogniser prompt.
        case refused(DictionaryStoreError)
    }

    /// One skipped line, by its number in the file.
    public struct Skip: Sendable, Equatable {
        public let line: Int
        public let problem: Problem
    }

    /// The new words, origin `added` with zero counters, in file order; removing them by identifier undoes the import.
    public let added: [DictionaryEntry]
    public let skipped: [Skip]

    public var duplicates: Int { skipped.count { $0.problem == .duplicate } }
    public var tooLong: Int { skipped.count { $0.problem == .tooLong } }
    /// Lines refused for what they hold rather than for repeating a word or for their length.
    public var refused: Int { skipped.count - duplicates - tooLong }
}

/// Why a whole word list was refused; nothing is written.
public enum PersonalWordListError: Error, Sendable, Equatable {
    /// The file is not UTF-8 text.
    case notText
    /// The file holds more lines with text than the limit.
    case tooManyLines(maximum: Int)
}
