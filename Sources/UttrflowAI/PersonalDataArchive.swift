// A versioned, local copy of the lists people build in Uttrflow.

public import Foundation
public import UttrflowCore
public import UttrflowDictionary

/// The personal dictionary and snippets a person can move between their own Macs.
public struct PersonalDataArchive: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let maximumSizeInBytes = 5 * 1024 * 1024
    public static let maximumSnippetCount = 1_000
    public static let maximumSnippetTriggerBytes = 256
    public static let maximumSnippetExpansionBytes = 16_384
    public static let maximumDictionaryWordBytes = 256

    public let version: Int
    public let dictionary: [DictionaryEntry]
    public let snippets: [Snippet]

    public init(dictionary: [DictionaryEntry], snippets: [Snippet], version: Int = currentVersion) {
        self.version = version
        self.dictionary = dictionary
        self.snippets = snippets
    }

    /// Encodes a complete snapshot, retaining identifiers, dates and usage counts.
    public func encoded() throws -> Data {
        if let limitError { throw limitError }
        guard isValid else { throw PersonalDataArchiveError.invalidContents }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumSizeInBytes else {
            throw PersonalDataArchiveError.archiveTooLarge
        }
        return data
    }

    /// Decodes and validates the entire file before a caller writes either store.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumSizeInBytes else {
            throw PersonalDataArchiveError.archiveTooLarge
        }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.version == currentVersion else { throw PersonalDataArchiveError.unsupportedVersion }
        if let limitError = archive.limitError { throw limitError }
        guard archive.isValid else { throw PersonalDataArchiveError.invalidContents }
        return archive
    }

    /// Adds entries whose spelling or trigger is not already present, keeping the current records on conflicts.
    public func merging(
        dictionary existingDictionary: [DictionaryEntry], snippets existingSnippets: [Snippet]
    )
        -> PersonalDataMerge
    {
        var words = Set(existingDictionary.map { $0.word.lowercased() })
        var mergedDictionary = existingDictionary
        var wordIndexes = Dictionary(
            existingDictionary.enumerated().map { ($0.element.word.lowercased(), $0.offset) },
            uniquingKeysWith: { _, newest in newest })
        var duplicateWords = 0
        for entry in dictionary {
            if words.insert(entry.word.lowercased()).inserted {
                wordIndexes[entry.word.lowercased()] = mergedDictionary.count
                mergedDictionary.append(entry)
            } else {
                duplicateWords += 1
                // When both copies are the shipped entry, the archive's identity and counters win.
                if entry.origin == .shipped,
                    let index = wordIndexes[entry.word.lowercased()],
                    mergedDictionary[index].origin == .shipped
                {
                    mergedDictionary[index] = entry
                }
            }
        }

        var triggers = Set(existingSnippets.map(\.triggerWords))
        var mergedSnippets = existingSnippets
        var duplicateSnippets = 0
        for snippet in snippets {
            if triggers.insert(snippet.triggerWords).inserted {
                mergedSnippets.append(snippet)
            } else {
                duplicateSnippets += 1
            }
        }

        return PersonalDataMerge(
            dictionary: mergedDictionary, snippets: mergedSnippets,
            duplicateWords: duplicateWords, duplicateSnippets: duplicateSnippets)
    }

    private var isValid: Bool {
        guard version == Self.currentVersion,
            Set(dictionary.map(\.id)).count == dictionary.count,
            Set(snippets.map(\.id)).count == snippets.count
        else { return false }
        return dictionary.allSatisfy {
            !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.timesUsed >= 0 && $0.timesReverted >= 0
        }
            && snippets.allSatisfy {
                !$0.triggerWords.isEmpty
                    && !$0.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.timesUsed >= 0
            }
    }

    private var limitError: PersonalDataArchiveError? {
        if snippets.count > Self.maximumSnippetCount { return .tooManySnippets }
        if snippets.contains(where: {
            $0.trigger.utf8.count > Self.maximumSnippetTriggerBytes
                || $0.expansion.utf8.count > Self.maximumSnippetExpansionBytes
        }) {
            return .snippetTooLong
        }
        if dictionary.contains(where: {
            $0.word.utf8.count > Self.maximumDictionaryWordBytes
                || ($0.pronunciation?.utf8.count ?? 0) > Self.maximumDictionaryWordBytes
        }) {
            return .dictionaryWordTooLong
        }
        return nil
    }
}

/// What the validated import would add, and how many conflicting records it skipped.
public struct PersonalDataMerge: Sendable, Equatable {
    public let dictionary: [DictionaryEntry]
    public let snippets: [Snippet]
    public let duplicateWords: Int
    public let duplicateSnippets: Int
}

public enum PersonalDataArchiveError: Error, Sendable {
    case unsupportedVersion
    case invalidContents
    case archiveTooLarge
    case tooManySnippets
    case snippetTooLong
    case dictionaryWordTooLong
}
