public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

/// The user's snippets, in their own file on this Mac. See `Docs/ai-snippet-store.md`.
public actor SnippetStore {
    /// The file, injected so a test writes into a temporary directory rather than real snippets.
    private let file: URL

    /// Uses the app's own file unless a test names another.
    public init(file: URL = SnippetStore.defaultFile()) {
        self.file = file
    }

    /// Where the snippets live, versioned in the name; only a test passes a `directory`.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("snippets.v1.json", in: directory)
    }

    // MARK: - Reading

    /// Every snippet, in creation order, so a row never moves while it is being edited.
    public func snippets() -> [Snippet] {
        load()
    }

    /// The matcher, built from what is on disk right now rather than from a list fetched earlier.
    public func expander() -> SnippetExpander {
        SnippetExpander(snippets: load())
    }

    // MARK: - Writing

    /// Keeps a snippet, replacing in place the one with the same identifier so an edit does not move it.
    @discardableResult
    public func save(_ snippet: Snippet) throws(SnippetStoreError) -> [Snippet] {
        guard !snippet.triggerWords.isEmpty else { throw .triggerHasNoWords }
        guard !TextTidy.collapseWhitespace(snippet.expansion).isEmpty else {
            throw .expansionIsEmpty
        }

        var kept = load()
        // Two snippets on one trigger is a question with no right answer, mid-dictation.
        let taken = kept.contains {
            $0.id != snippet.id && $0.triggerWords == snippet.triggerWords
        }
        guard !taken else { throw .triggerAlreadyUsed }

        if let existing = kept.firstIndex(where: { $0.id == snippet.id }) {
            kept[existing] = snippet
        } else {
            kept.append(snippet)
        }
        try persist(kept)
        return kept
    }

    /// Writes what the editor holds, carrying over identity, date and counts. See `Docs/ai-snippet-store.md`.
    @discardableResult
    public func save(
        trigger: String, expansion: String, replacing: UUID?, created: Date
    ) throws(SnippetStoreError) -> [Snippet] {
        let existing = replacing.flatMap { id in load().first { $0.id == id } }
        return try save(
            Snippet(
                id: existing?.id ?? UUID(),
                trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
                expansion: expansion,
                created: existing?.created ?? created,
                timesUsed: existing?.timesUsed ?? 0,
                lastUsed: existing?.lastUsed))
    }

    /// Forgets one snippet, and answers with what is left; an absent identifier is not an error.
    @discardableResult
    public func delete(_ id: UUID) throws(SnippetStoreError) -> [Snippet] {
        let kept = load().filter { $0.id != id }
        try persist(kept)
        return kept
    }

    /// Forgets everything, reaching the disk now rather than at the next write.
    public func deleteEverything() throws(SnippetStoreError) {
        try persist([])
    }

    /// Counts every firing in `ids`, ignoring identifiers that are gone and writing only if any counted.
    @discardableResult
    public func recordUse(of ids: [UUID], at when: Date) throws(SnippetStoreError) -> [Snippet] {
        var kept = load()
        var counted = false
        for id in ids {
            guard let index = kept.firstIndex(where: { $0.id == id }) else { continue }
            kept[index] = kept[index].used(at: when)
            counted = true
        }
        if counted { try persist(kept) }
        return kept
    }

    // MARK: - The file

    /// Reads the file, answering with nothing when there is nothing readable there.
    private func load() -> [Snippet] {
        guard let data = try? Data(contentsOf: file),
            let snippets = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return [] }
        return snippets
    }

    /// Writes the whole list atomically, or removes the file when nothing is left to keep.
    private func persist(_ snippets: [Snippet]) throws(SnippetStoreError) {
        do {
            guard !snippets.isEmpty else {
                try removeFile()
                return
            }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snippets).write(to: file, options: .atomic)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Deletes the file if it is there. Nothing to delete is success, not a failure.
    private func removeFile() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: file)
    }
}
