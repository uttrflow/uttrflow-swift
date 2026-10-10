// Validates and merges a local personal-data archive into the two stores.

public import UttrflowDictionary
import struct UttrflowCore.Snippet
public import struct Foundation.Data
public import struct Foundation.Date
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

    /// Validates the whole archive, then merges each list inside its store; a failed second write undoes the first.
    public static func importArchive(
        _ data: Data,
        into dictionary: PersonalDictionaryStore,
        and snippets: SnippetStore,
        importedAt: Date = Date()
    ) async throws -> PersonalDataImportReport {
        let archive = try PersonalDataArchive.decode(data)
        guard
            archive.dictionary.allSatisfy({
                PhoneticIndex.refusal(for: $0) == nil
            })
        else { throw PersonalDataArchiveError.invalidContents }

        // Snippets go first because their merge only appends, so removing what it added is an exact undo.
        let snippetMerge = try await snippets.replaceAll { current in
            let merge = archive.mergedSnippets(into: current)
            return (merge.records, merge)
        }
        let words: (kept: [DictionaryEntry], outcome: PersonalDataMerge<DictionaryEntry>)
        do {
            words = try await dictionary.replaceAll { current in
                let merge = archive.mergedDictionary(into: current, importedAt: importedAt)
                return (merge.records, merge)
            }
        } catch {
            await undo(snippetMerge.added, in: snippets)
            throw error
        }
        // Refusals go last: they only bind learning, and adding words removes none of them.
        let refusals: RefusalImport
        do {
            refusals = try await dictionary.importRefusals(archive.refused)
        } catch {
            let added = Set(words.outcome.added.map(\.id))
            _ = try? await dictionary.replaceAll { current in (current.filter { !added.contains($0.id) }, ())
            }
            await undo(snippetMerge.added, in: snippets)
            throw error
        }
        return PersonalDataImportReport(
            duplicateWords: words.outcome.duplicates, duplicateSnippets: snippetMerge.duplicates,
            skippedInferredWords: words.outcome.records.count - words.kept.count,
            snippetsSayingCommands: snippetMerge.added.count { $0.collidingCommand != nil },
            refusedWords: refusals.added, lapsedRefusals: refusals.lapsed)
    }

    /// Removes the snippets an import appended, which is an exact undo because their merge only appends.
    private static func undo(_ added: [Snippet], in snippets: SnippetStore) async {
        let ids = Set(added.map(\.id))
        try? await snippets.replaceAll { current in (current.filter { !ids.contains($0.id) }, ()) }
    }

    /// Reads a user-selected word list under the archive's byte ceiling, then adds every line the editor would accept.
    public static func importWordList(
        from source: URL, into dictionary: PersonalDictionaryStore
    ) async throws -> PersonalWordListReport {
        try await importWordList(readArchive(from: source), into: dictionary)
    }

    /// Refuses a file that is not a word list before writing, then plans against the words held at the moment of writing.
    public static func importWordList(
        _ data: Data, into dictionary: PersonalDictionaryStore, importedAt: Date = Date()
    ) async throws -> PersonalWordListReport {
        let list = try PersonalWordList(decoding: data)
        return try await dictionary.replaceAll { current in
            let report = list.plan(over: current, importedAt: importedAt)
            return (current + report.added, report)
        }.outcome
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
    /// Snippets imported although their trigger says a spoken command, so they never fire and the command wins.
    public let snippetsSayingCommands: Int
    /// Spellings the archive refused that this Mac now refuses too.
    public let refusedWords: Int
    /// Refusals dropped, oldest first, to stay within `PersonalDictionaryStore.maximumRefusedWords`.
    public let lapsedRefusals: Int
}
