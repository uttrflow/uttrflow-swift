// Which applied words a person replaced by hand after the dictation landed. See Docs/app-dictionary-store.md.

public import struct Foundation.UUID

/// Decides, from what was inserted and what the field reads later, which applied entries were edited away.
public enum EditAway {
    /// One entry a dictation applied, by the spelling it wrote into the insertion.
    public struct Applied: Sendable, Equatable {
        public let entryID: UUID
        public let word: String

        public init(entryID: UUID, word: String) {
            self.entryID = entryID
            self.word = word
        }
    }

    /// Entries whose word is gone while both neighbours stay; the caller sends each through `recordRevert(of:)`.
    public static func editedAway(_ applied: [Applied], inserted: String, fieldNow: String) -> [UUID] {
        let before = words(of: inserted)
        let after = words(of: fieldNow)
        return applied.compactMap { entry in
            let target = words(of: entry.word)
            guard !target.isEmpty, let start = position(of: target, in: before),
                position(of: target, in: after) == nil
            else { return nil }
            let left = Array(before[..<start])
            let right = Array(before[(start + target.count)...])
            guard !(left.isEmpty && right.isEmpty), keepsNeighbours(left, right, in: after) else {
                return nil
            }
            return entry.entryID
        }
    }

    /// Whether the words before the target and the words after it both survive, in order, the left run first.
    private static func keepsNeighbours(_ left: [String], _ right: [String], in field: [String]) -> Bool {
        guard let leftEnd = left.isEmpty ? 0 : position(of: left, in: field).map({ $0 + left.count }) else {
            return false
        }
        return right.isEmpty || position(of: right, in: Array(field[leftEnd...])) != nil
    }

    /// Lower-cased words with their surrounding punctuation dropped, so a moved comma is not an edit.
    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let trimmed = token.lowercased().trimmingCharacters(in: punctuation)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static let punctuation = Set(".,;:!?\"'()[]{}")

    /// Where `run` first starts inside `words`, or `nil` when it does not occur.
    private static func position(of run: [String], in words: [String]) -> Int? {
        guard run.count <= words.count else { return nil }
        return (0...(words.count - run.count)).first { Array(words[$0..<($0 + run.count)]) == run }
    }
}

extension String {
    /// The string with leading and trailing characters in `set` removed.
    fileprivate func trimmingCharacters(in set: Set<Character>) -> String {
        var slice = Substring(self)
        while let first = slice.first, set.contains(first) { slice = slice.dropFirst() }
        while let last = slice.last, set.contains(last) { slice = slice.dropLast() }
        return String(slice)
    }
}
