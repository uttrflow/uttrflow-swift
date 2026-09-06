public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

/// The words this user says that a general model would not expect. See `Docs/app-dictionary-store.md`.
public actor PersonalDictionaryStore {
    /// The file, injected so a test writes into a temporary directory rather than a real dictionary.
    private let file: URL

    /// The dictionary arranged by sound, built on demand and thrown away by every write.
    private var cachedIndex: PhoneticIndex?

    /// Terms seen and said but not yet often enough to keep; never written down, so no page clears it.
    private var sightings = SightingLedger()

    public init(file: URL = PersonalDictionaryStore.defaultFile()) {
        self.file = file
    }

    /// Where the dictionary lives by default; versioned in the name so a new shape can sit beside it.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("dictionary.v1.json", in: directory)
    }

    // MARK: - Reading

    /// Every word in the order it was added, retired ones included so the user can still see them.
    public func allEntries() -> [DictionaryEntry] {
        load()
    }

    /// The dictionary arranged by sound. Built once and reused until something changes.
    public func index() -> PhoneticIndex {
        if let cachedIndex { return cachedIndex }
        let built = PhoneticIndex(entries: load())
        cachedIndex = built
        return built
    }

    // MARK: - Writing

    /// Teaches the dictionary a word, replacing any entry that spells it the same way.
    @discardableResult
    public func add(_ entry: DictionaryEntry) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let spelling = entry.word.lowercased()
        let kept =
            load().filter { $0.id != entry.id && $0.word.lowercased() != spelling } + [entry]
        try persist(kept)
        return kept
    }

    /// Writes what the user typed in as a word of their own. See `Docs/app-dictionary-store.md`.
    @discardableResult
    public func add(
        word: String, pronunciation: String, at moment: Date
    ) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let spelling = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spelling.isEmpty else { throw .wordIsEmpty }
        guard !load().contains(where: { $0.word.lowercased() == spelling.lowercased() }) else {
            throw .wordAlreadyKnown
        }
        let sound = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        return try add(
            DictionaryEntry(
                word: spelling, pronunciation: sound.isEmpty ? nil : sound, origin: .added,
                firstSeen: moment))
    }

    /// Forgets one word; an identifier that is not there is not an error.
    @discardableResult
    public func remove(_ id: UUID) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let existing = load()
        let kept = existing.filter { $0.id != id }
        // A word Uttrflow inferred and the user then deleted must not simply be counted up again.
        if let gone = existing.first(where: { $0.id == id }), gone.origin != .added {
            sightings.refuse(gone.word)
        }
        try persist(kept)
        return kept
    }

    /// Forgets every word, the user's own included; ``removeLearned()`` is almost always the one meant.
    public func removeEverything() throws(DictionaryStoreError) {
        sightings.forgetEverything()
        try persist([])
    }

    /// Forgets every inference and keeps the user's own words. See `Docs/app-dictionary-store.md`.
    @discardableResult
    public func removeLearned() throws(DictionaryStoreError) -> [DictionaryEntry] {
        // The half-counted evidence goes with the entries, or the button is a liar by one dictation.
        sightings.forgetEverything()
        let kept = load().filter { $0.origin == .added }
        try persist(kept)
        return kept
    }

    /// Learns from a landed dictation; `heard` is the raw transcript. See `Docs/app-dictionary-store.md`.
    @discardableResult
    public func learn(
        heard: String, wrote: String, seeing context: AppContext, at moment: Date
    ) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let existing = load()
        // What is already held, so neither path adds a second row or reaches the replacing `add`.
        var known = Set(existing.map { $0.word.lowercased() })
        var learnt: [DictionaryEntry] = []

        if let corrected = LearnableWords.corrected(over: context.selectedText, wrote: wrote),
            known.insert(corrected.lowercased()).inserted
        {
            learnt.append(DictionaryEntry(word: corrected, origin: .learned, firstSeen: moment))
        }

        // Filtered before the tally, so a word already held stops being counted rather than counted on.
        let seen = LearnableWords.seenAndSaid(heard: heard, seeing: context)
            .filter { !known.contains($0.lowercased()) }
        learnt += sightings.record(seen).map {
            DictionaryEntry(word: $0, origin: .observed, firstSeen: moment)
        }

        guard !learnt.isEmpty else { return [] }
        try persist(existing + learnt)
        return learnt
    }

    /// Notes that an entry was applied to a dictation, answering with it so a caller sees it retire.
    @discardableResult
    public func recordUse(of id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try update(id) { $0.timesUsed += 1 }
    }

    /// Notes that the user undid a dictation this entry was applied to, which is what retires a word.
    @discardableResult
    public func recordRevert(of id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try update(id) { $0.timesReverted += 1 }
    }

    /// Clears a retired entry's undo count, keeping its uses. See `Docs/app-dictionary-store.md`.
    @discardableResult
    public func restore(_ id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try update(id) { $0.timesReverted = 0 }
    }

    /// The one place an entry is found, changed and written back, so the counters cannot disagree.
    private func update(
        _ id: UUID, _ change: (inout DictionaryEntry) -> Void
    ) throws(DictionaryStoreError) -> DictionaryEntry? {
        var entries = load()
        guard let position = entries.firstIndex(where: { $0.id == id }) else { return nil }
        change(&entries[position])
        try persist(entries)
        return entries[position]
    }

    // MARK: - The file

    /// Reads the file, answering with nothing when there is nothing readable there.
    private func load() -> [DictionaryEntry] {
        guard let data = try? Data(contentsOf: file),
            let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
        else { return [] }
        return entries
    }

    /// Writes the whole list atomically, or removes the file when nothing is left to keep.
    private func persist(_ entries: [DictionaryEntry]) throws(DictionaryStoreError) {
        // Dropped before the write, not after: an index rebuilt from the old list is right either way.
        cachedIndex = nil
        do {
            guard !entries.isEmpty else {
                try removeFile()
                return
            }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Deletes the file if it is there; nothing to delete is success, not a failure.
    private func removeFile() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: file)
    }
}
