// Validates and merges a local personal-data archive into the two stores.

public import UttrflowDictionary
public import struct Foundation.Data
public import struct Foundation.URL
public import class Foundation.FileHandle

public enum PersonalDataTransfer {
    /// Reads a user-selected archive with a strict byte ceiling before validating or merging it.
    public static func importArchive(
        from source: URL,
        into dictionary: PersonalDictionaryStore,
        and snippets: SnippetStore
    ) async throws -> PersonalDataImportReport {
        let data = try readArchive(from: source)
        return try await importArchive(data, into: dictionary, and: snippets)
    }

    /// Decodes and validates the complete input before either list is written.
    public static func importArchive(
        _ data: Data,
        into dictionary: PersonalDictionaryStore,
        and snippets: SnippetStore
    ) async throws -> PersonalDataImportReport {
        let archive = try PersonalDataArchive.decode(data)
        guard
            archive.dictionary.allSatisfy({
                PhoneticIndex.supports(word: $0.word, pronunciation: $0.pronunciation)
            })
        else { throw PersonalDataArchiveError.invalidContents }

        let merged = archive.merging(
            dictionary: await dictionary.allEntries(), snippets: await snippets.snippets())
        let kept = try await dictionary.replaceAll(merged.dictionary)
        try await snippets.replaceAll(merged.snippets)
        return PersonalDataImportReport(
            duplicateWords: merged.duplicateWords, duplicateSnippets: merged.duplicateSnippets,
            skippedInferredWords: merged.dictionary.count - kept.count)
    }

    private static func readArchive(from source: URL) throws -> Data {
        let knownSize = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let knownSize, knownSize > PersonalDataArchive.maximumSizeInBytes {
            throw PersonalDataArchiveError.archiveTooLarge
        }

        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var data = Data()
        while data.count < PersonalDataArchive.maximumSizeInBytes {
            let remaining = PersonalDataArchive.maximumSizeInBytes - data.count
            let requested = min(64 * 1024, remaining + 1)
            guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else { return data }
            guard chunk.count <= remaining else { throw PersonalDataArchiveError.archiveTooLarge }
            data.append(chunk)
        }
        let extraByte = try handle.read(upToCount: 1)
        guard extraByte?.isEmpty ?? true else {
            throw PersonalDataArchiveError.archiveTooLarge
        }
        return data
    }
}

/// What an import skipped: duplicates, and the weakest inferred words beyond the store's bound.
public struct PersonalDataImportReport: Sendable, Equatable {
    public let duplicateWords: Int
    public let duplicateSnippets: Int
    public let skippedInferredWords: Int
}
