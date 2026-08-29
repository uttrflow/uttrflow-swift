public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

/// The user's snippets, kept on this Mac between launches.
///
/// Its own file under Application Support, beside the history and the dictionary rather
/// than inside either: these are neither the user's words nor a spelling the app
/// learned, they are text the user wrote once and expects to still be there in a year.
/// Nothing ages them out, and nothing else may clear them by accident.
///
/// An actor, for the reason the history store gives at length — the readers are windows
/// and the writer is a dictation that has already finished, so waiting should be a
/// suspension rather than a blocked main thread.
///
/// Nothing is cached. The dictionary store caches because it is read before *and* after
/// every dictation and rebuilds an index each time; this is read once per dictation and
/// decodes a handful of records, so the certainty that the file is the only truth is
/// worth more than the read it would save.
public actor SnippetStore {
    /// The file. Injected so a test writes into a temporary directory and never into
    /// the snippets of whoever is running it.
    private let file: URL

    public init(file: URL = SnippetStore.defaultFile()) {
        self.file = file
    }

    /// Where the snippets live when the app has not been told otherwise.
    ///
    /// Versioned in the name so that a shape too different to read field by field can
    /// one day be introduced beside this one rather than on top of it.
    ///
    /// - Parameter directory: The container to put Uttrflow's folder in. Nothing but a
    ///   test has a reason to pass one.
    /// - Returns: The file the snippets are read from and written to.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        directory.appending(path: "Uttrflow/snippets.v1.json", directoryHint: .notDirectory)
    }

    // MARK: - Reading

    /// Every snippet, in the order they were created.
    ///
    /// Creation order and not most-used or most-recent, because the list on screen is
    /// edited in place: a row that jumps somewhere else the moment you save it is a row
    /// you then have to hunt for. Sorting is the interface's to do, and it can do it
    /// without the store's order changing underneath it.
    public func snippets() -> [Snippet] {
        load()
    }

    /// The matcher, built from what is on disk.
    ///
    /// Offered here rather than left to each caller so that there is one place where a
    /// stored snippet becomes a rule, and no chance of a caller building one from a
    /// list it fetched some time ago.
    public func expander() -> SnippetExpander {
        SnippetExpander(snippets: load())
    }

    // MARK: - Writing

    /// Adds a snippet, or replaces the one with the same identifier, and answers with
    /// the list as it now stands.
    ///
    /// Replaced in place rather than removed and appended, so that editing a row does
    /// not move it.
    ///
    /// - Parameter snippet: The snippet to keep.
    /// - Returns: Every snippet, in creation order.
    /// - Throws: ``SnippetStoreError`` when the snippet could never fire, when another
    ///   snippet already answers to its trigger, or when the disk refused the write.
    @discardableResult
    public func save(_ snippet: Snippet) throws(SnippetStoreError) -> [Snippet] {
        guard !snippet.triggerWords.isEmpty else { throw .triggerHasNoWords }
        guard !TextTidy.collapseWhitespace(snippet.expansion).isEmpty else {
            throw .expansionIsEmpty
        }

        var kept = load()
        // Two snippets answering to one trigger is a question with no right answer, and
        // the wrong place to discover it is halfway through a dictation. The matcher
        // would pick one and be consistent about it; the user would have no idea which.
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

    /// Writes what the user typed into the editor, keeping everything about a snippet
    /// they did not type.
    ///
    /// The reason this exists rather than the caller building a ``Snippet`` and handing
    /// it to ``save(_:)``: on an edit, the identity, the date it was created and both
    /// use counters have to be carried over from the snippet being replaced, and a
    /// caller that forgot any of them would silently make a two-year-old snippet look
    /// new and reset what had been counted about it. That is a decision about what a
    /// snippet *is*, so it belongs here and not in whichever window happens to be open.
    ///
    /// - Parameters:
    ///   - trigger: What the user says, as typed. Surrounding space is not theirs.
    ///   - expansion: What is put in its place, verbatim — **not** trimmed, because a
    ///     snippet ending in a newline is a snippet that ends in a newline.
    ///   - replacing: The snippet being edited, or `nil` for a new one. An identifier
    ///     that is no longer there is treated as new: the row was deleted underneath the
    ///     editor, and refusing would lose what the user had typed.
    ///   - created: The moment to record, when this turns out to be a new snippet.
    /// - Returns: Every snippet, in creation order.
    /// - Throws: Whatever ``save(_:)`` throws — the rules about what may be kept are
    ///   its, not this one's.
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

    /// Forgets one snippet, and answers with what is left.
    ///
    /// An identifier that is not there is not an error: the caller asked for it to be
    /// gone, and it is.
    ///
    /// - Parameter id: The snippet to remove.
    /// - Returns: Every snippet still kept, in creation order.
    /// - Throws: ``SnippetStoreError/couldNotWrite`` when the disk refused the change.
    @discardableResult
    public func delete(_ id: UUID) throws(SnippetStoreError) -> [Snippet] {
        let kept = load().filter { $0.id != id }
        try persist(kept)
        return kept
    }

    /// Forgets everything.
    ///
    /// Reaches the disk inside this call rather than at the next write: a user who
    /// clears their snippets and then quits must not find them still there.
    public func deleteEverything() throws(SnippetStoreError) {
        try persist([])
    }

    /// Counts the snippets that fired in one dictation.
    ///
    /// Takes identifiers rather than a ``SnippetExpansion`` so the store stays ignorant
    /// of the matcher; the call site passes ``SnippetExpansion/usedSnippetIDs``. A
    /// snippet that fired twice appears twice and is counted twice, which is what the
    /// user did.
    ///
    /// Identifiers that no longer exist are ignored, and a call that changes nothing
    /// does not touch the disk — a dictation with no expansions in it must not rewrite
    /// the file.
    ///
    /// - Parameters:
    ///   - ids: The snippets that fired, in any order.
    ///   - when: The instant they fired.
    /// - Returns: Every snippet, in creation order, with the counts brought up to date.
    /// - Throws: ``SnippetStoreError/couldNotWrite`` when the disk refused the change.
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
    ///
    /// Absent, unreadable, truncated, hand-edited, or written by a build that knew a
    /// different shape — to a user those all mean the same thing, which is that the app
    /// should still open. Salvaging record by record is not attempted: our own writes
    /// are atomic, so the realistic corruption is a whole file somebody mangled, and
    /// half a list restored is harder to explain than none.
    private func load() -> [Snippet] {
        guard let data = try? Data(contentsOf: file),
            let snippets = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return [] }
        return snippets
    }

    /// Writes the whole list, or removes the file when nothing is left to keep.
    ///
    /// Atomically, so that a crash or a full disk cannot leave behind the truncated
    /// file ``load()`` would then have to throw away. Removing rather than writing an
    /// empty array means an emptied list leaves nothing of the user's on disk at all.
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
