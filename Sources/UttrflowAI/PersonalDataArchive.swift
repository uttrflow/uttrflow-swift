// A versioned, local copy of the lists people build in Uttrflow.

public import Foundation
public import UttrflowCore
public import UttrflowDictionary

/// The personal dictionary, snippets and refused words a person can move between their own Macs.
public struct PersonalDataArchive: Codable, Sendable, Equatable {
    /// What this build writes; version 2 added `refused`, and a version 1 file still imports with none.
    public static let currentVersion = 2
    /// Every version this build reads.
    public static let supportedVersions: ClosedRange<Int> = 1...currentVersion
    public static let maximumSizeInBytes = 5 * 1024 * 1024
    public static let maximumSnippetCount = 1_000
    public static let maximumSnippetTriggerBytes = 256
    public static let maximumSnippetExpansionBytes = 16_384
    public static let maximumDictionaryWordBytes = 256
    /// Imported words all count as added and escape the inferred-word cap, so the archive bounds them itself.
    public static let maximumDictionaryEntryCount = 1_000
    /// Refused words an archive may name; import keeps the newest of them within the store's own bound.
    public static let maximumRefusedWordCount = 5_000

    public let version: Int
    public let dictionary: [DictionaryEntry]
    public let snippets: [Snippet]
    /// Spellings the person deleted and does not want learned again, oldest first.
    public let refused: [String]

    public init(
        dictionary: [DictionaryEntry], snippets: [Snippet], refused: [String] = [],
        version: Int = currentVersion
    ) {
        self.version = version
        self.dictionary = dictionary
        self.snippets = snippets
        self.refused = refused
    }

    private enum CodingKeys: String, CodingKey {
        case version, dictionary, snippets, refused
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        dictionary = try container.decode([DictionaryEntry].self, forKey: .dictionary)
        snippets = try container.decode([Snippet].self, forKey: .snippets)
        refused = try container.decodeIfPresent([String].self, forKey: .refused) ?? []
    }

    /// Writes `refused` only when it holds a word, so an archive without refusals keeps the version 1 shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(dictionary, forKey: .dictionary)
        try container.encode(snippets, forKey: .snippets)
        if !refused.isEmpty { try container.encode(refused, forKey: .refused) }
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
        guard supportedVersions.contains(archive.version) else {
            throw PersonalDataArchiveError.unsupportedVersion
        }
        if let limitError = archive.limitError { throw limitError }
        guard archive.isValid else { throw PersonalDataArchiveError.invalidContents }
        return archive
    }

    /// Adds new spellings with only their word and every pronunciation, since a file can come from anyone. See `Docs/personal-data-archive.md`.
    public func mergedDictionary(
        into existing: [DictionaryEntry], importedAt: Date
    ) -> PersonalDataMerge<DictionaryEntry> {
        var ids = Set(existing.map(\.id))
        var merged = existing
        var spellings = Set(existing.map { $0.word.lowercased() })
        var added: [DictionaryEntry] = []
        var duplicates = 0
        for entry in dictionary {
            guard spellings.insert(entry.word.lowercased()).inserted else {
                duplicates += 1
                continue
            }
            // An identifier already held by another word is a different record, so it gets its own.
            let id = ids.contains(entry.id) ? UUID() : entry.id
            let kept = DictionaryEntry(
                id: id, word: entry.word, pronunciations: entry.pronunciations, origin: .added,
                firstSeen: importedAt, applications: entry.applications)
            ids.insert(kept.id)
            merged.append(kept)
            added.append(kept)
        }
        return PersonalDataMerge(records: merged, added: added, duplicates: duplicates)
    }

    /// Adds snippets whose trigger is not already used, keeping the current record on a conflict.
    public func mergedSnippets(into existing: [Snippet]) -> PersonalDataMerge<Snippet> {
        var ids = Set(existing.map(\.id))
        var triggers = Set(existing.map(\.triggerWords))
        var merged = existing
        var added: [Snippet] = []
        var duplicates = 0
        for snippet in snippets {
            guard triggers.insert(snippet.triggerWords).inserted else {
                duplicates += 1
                continue
            }
            // An identifier already held by another trigger is a different record, so it gets its own.
            let kept = ids.insert(snippet.id).inserted ? snippet : snippet.withFreshID()
            ids.insert(kept.id)
            merged.append(kept)
            added.append(kept)
        }
        return PersonalDataMerge(records: merged, added: added, duplicates: duplicates)
    }

    private var isValid: Bool {
        // Refusals arrived with version 2, so a version 1 file naming them was not written by Uttrflow.
        guard Self.supportedVersions.contains(version), version >= 2 || refused.isEmpty,
            Set(dictionary.map(\.id)).count == dictionary.count,
            Set(snippets.map(\.id)).count == snippets.count
        else { return false }
        guard refused.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return false
        }
        return dictionary.allSatisfy {
            !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.timesUsed >= 0 && $0.timesReverted >= 0
        }
            && snippets.allSatisfy { (try? SnippetStore.validate($0)) != nil && $0.timesUsed >= 0 }
    }

    private var limitError: PersonalDataArchiveError? {
        if snippets.count > Self.maximumSnippetCount { return .tooManySnippets }
        if dictionary.count > Self.maximumDictionaryEntryCount { return .tooManyDictionaryEntries }
        if snippets.contains(where: {
            $0.trigger.utf8.count > Self.maximumSnippetTriggerBytes
                || $0.expansion.utf8.count > Self.maximumSnippetExpansionBytes
        }) {
            return .snippetTooLong
        }
        if refused.count > Self.maximumRefusedWordCount { return .tooManyRefusedWords }
        if dictionary.contains(where: {
            $0.word.utf8.count > Self.maximumDictionaryWordBytes
                || $0.pronunciations.contains { $0.utf8.count > Self.maximumDictionaryWordBytes }
        }) || refused.contains(where: { $0.utf8.count > Self.maximumDictionaryWordBytes }) {
            return .dictionaryWordTooLong
        }
        let spellings =
            dictionary.flatMap { [$0.word] + $0.pronunciations } + snippets.map(\.trigger) + refused
        if spellings.contains(where: Self.holdsHiddenCharacters) { return .hiddenCharacters }
        return nil
    }

    /// Whether text carries a control or bidirectional formatting character, which can hide or reorder what it reads as.
    static func holdsHiddenCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            $0.properties.generalCategory == .control || $0.properties.isBidiControl
        }
    }
}

/// One list after an import: every record, the ones the archive added, and how many conflicts it skipped.
public struct PersonalDataMerge<Record: Sendable & Equatable>: Sendable, Equatable {
    public let records: [Record]
    public let added: [Record]
    public let duplicates: Int
}

public enum PersonalDataArchiveError: Error, Sendable {
    case unsupportedVersion
    case invalidContents
    case archiveTooLarge
    case tooManySnippets
    case snippetTooLong
    case dictionaryWordTooLong
    case tooManyDictionaryEntries
    case tooManyRefusedWords
    case hiddenCharacters
}

extension Snippet {
    fileprivate func withFreshID() -> Snippet {
        Snippet(
            trigger: trigger, expansion: expansion, created: created, timesUsed: timesUsed,
            lastUsed: lastUsed, applications: applications)
    }
}
