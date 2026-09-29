public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder
public import struct Foundation.CocoaError

/// The words this user says that a general model would not expect. See `Docs/app-dictionary-store.md`.
public actor PersonalDictionaryStore {
    /// The file, injected so a test writes into a temporary directory rather than a real dictionary.
    private let file: URL

    /// The file's decoded contents, reread only when the file changed on disk.
    var cache: CachedStoredList<[DictionaryEntry]>

    /// The dictionary arranged by sound, and the cache generation it was built from.
    private var cachedIndex: (generation: Int, index: PhoneticIndex)?

    /// Terms seen and said but not yet often enough to keep, and the words deleted; read from disk on first use.
    private var ledger: SightingLedger?

    public init(file: URL = PersonalDictionaryStore.defaultFile()) {
        self.file = file
        self.cache = CachedStoredList(file: file)
    }

    /// Where the dictionary lives by default; versioned in the name so a new shape can sit beside it.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("dictionary.v1.json", in: directory)
    }

    /// Which shipped words this dictionary has been given, named after it so two never share one record.
    private var seedRecord: URL {
        file.deletingLastPathComponent().appending(
            path: "\(file.deletingPathExtension().lastPathComponent).seeded.json",
            directoryHint: .notDirectory)
    }

    /// Which words the user deleted, so a relaunch does not learn them again. See `Docs/app-dictionary-store.md`.
    private var refusalRecord: URL {
        file.deletingLastPathComponent().appending(
            path: "\(file.deletingPathExtension().lastPathComponent).refused.json",
            directoryHint: .notDirectory)
    }

    // MARK: - Reading

    /// Every word in the order it was added, retired ones included so the user can still see them.
    public func allEntries() -> [DictionaryEntry] {
        load()
    }

    /// The dictionary arranged by sound. Rebuilt from memory only when the entries changed.
    public func index() -> PhoneticIndex {
        let entries = load()
        if let cachedIndex, cachedIndex.generation == cache.generation { return cachedIndex.index }
        let built = PhoneticIndex(entries: entries)
        cachedIndex = (cache.generation, built)
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

    /// Writes each word this build ships knowing, once ever; a word the user then deletes stays deleted.
    @discardableResult
    public func seedShippedWords(at moment: Date) throws(DictionaryStoreError) -> [DictionaryEntry] {
        try seed(ShippedWords.entries(at: moment))
    }

    /// Seeds the given shipped entries, skipping any spelling this dictionary was offered before.
    func seed(_ shipped: [DictionaryEntry]) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let offered = try offeredSpellings()
        let unoffered = shipped.filter { !offered.contains($0.word.lowercased()) }
        guard !unoffered.isEmpty else { return [] }
        let existing = load()
        let known = Set(existing.map { $0.word.lowercased() })
        let seeded = unoffered.filter { !known.contains($0.word.lowercased()) }
        // Recorded only once the words are on disk, so a failed write is retried; a retry skips any word already there.
        if !seeded.isEmpty { try persist(existing + seeded) }
        try recordOffered(offered.union(shipped.map { $0.word.lowercased() }))
        return seeded
    }

    /// The seed record: the list version last applied, and every shipped spelling ever offered.
    private struct SeedRecord: Codable {
        let version: Int
        let offered: [String]?
    }

    /// A missing record is new; an unreadable one is not evidence that a deleted word may return.
    private func offeredSpellings() throws(DictionaryStoreError) -> Set<String> {
        let data: Data
        do {
            data = try Data(contentsOf: seedRecord)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            throw .couldNotReadSeedRecord
        }
        guard let record = try? JSONDecoder().decode(SeedRecord.self, from: data),
            record.version >= 0
        else { throw .couldNotReadSeedRecord }
        if let offered = record.offered { return Set(offered.map { $0.lowercased() }) }
        // A record written before spellings were listed names only a version, and version 1 was this list.
        return record.version >= 1 ? ShippedWords.versionOneSpellings : []
    }

    /// Notes every shipped spelling offered so far, which is what stops a deleted word returning.
    private func recordOffered(_ offered: Set<String>) throws(DictionaryStoreError) {
        let record = SeedRecord(version: ShippedWords.version, offered: offered.sorted())
        do {
            try PrivateFile.write(JSONEncoder().encode(record), to: seedRecord)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Forgets one word; an identifier that is not there is not an error.
    @discardableResult
    public func remove(_ id: UUID) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let existing = load()
        let kept = existing.filter { $0.id != id }
        // A deleted word must not simply be counted up again, whoever first put it there.
        if let gone = existing.first(where: { $0.id == id }) {
            var sightings = sightingLedger()
            sightings.refuse(gone.word)
            ledger = sightings
            try recordRefusals(sightings.refusals)
        }
        try persist(kept)
        return kept
    }

    /// Forgets every word, the user's own included; ``removeLearned()`` is almost always the one meant.
    public func removeEverything() throws(DictionaryStoreError) {
        try forgetSightings()
        try persist([])
        do { try LocalStore.removeSetAside(file) } catch { throw .couldNotWrite }
    }

    /// Forgets every inference and keeps the user's own words and this build's. See `Docs/app-dictionary-store.md`.
    @discardableResult
    public func removeLearned() throws(DictionaryStoreError) -> [DictionaryEntry] {
        // The half-counted evidence goes with the entries, or the button is a liar by one dictation.
        try forgetSightings()
        // A shipped word was inferred from nothing, so there is nothing about it to forget.
        let kept = load().filter { $0.origin == .added || $0.origin == .shipped }
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
        var sightings = sightingLedger()

        if let corrected = LearnableWords.corrected(over: context.selectedText, wrote: wrote),
            !sightings.isRefused(corrected),
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
        ledger = sightings

        guard !learnt.isEmpty else { return [] }
        try persist(existing + learnt)
        return learnt
    }

    /// Notes that an entry was applied to a dictation, answering with it so a caller sees it retire.
    @discardableResult
    public func recordUse(of id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try recordUse(of: [id]).first
    }

    /// Counts one dictation against each distinct entry in a single write, answering with those counted.
    @discardableResult
    public func recordUse(of ids: [UUID]) throws(DictionaryStoreError) -> [DictionaryEntry] {
        // Saturates rather than trapping, so a counter already at its ceiling stays there.
        try update(Set(ids)) { $0.timesUsed = DictionaryEntry.clamped($0.timesUsed + 1) }
    }

    /// Notes that the user undid a dictation this entry was applied to, which is what retires a word.
    @discardableResult
    public func recordRevert(of id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try update(id) { $0.timesReverted = DictionaryEntry.clamped($0.timesReverted + 1) }
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
        try update([id], change).first
    }

    /// Changes every entry named in `ids` and writes once, or not at all when none of them is there.
    private func update(
        _ ids: Set<UUID>, _ change: (inout DictionaryEntry) -> Void
    ) throws(DictionaryStoreError) -> [DictionaryEntry] {
        guard !ids.isEmpty else { return [] }
        var entries = load()
        let positions = entries.indices.filter { ids.contains(entries[$0].id) }
        guard !positions.isEmpty else { return [] }
        for position in positions { change(&entries[position]) }
        try persist(entries)
        return positions.map { entries[$0] }
    }

    // MARK: - Refusals

    /// The ledger, starting from the refusals on disk the first time it is needed.
    private func sightingLedger() -> SightingLedger {
        if let ledger { return ledger }
        let loaded = SightingLedger(refusing: storedRefusals())
        ledger = loaded
        return loaded
    }

    /// The refusals a previous run wrote down; a missing or unreadable record refuses nothing.
    private func storedRefusals() -> [String] {
        guard let data = try? Data(contentsOf: refusalRecord),
            let words = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return words
    }

    /// Writes the refusals down, or removes the record when none is left.
    private func recordRefusals(_ words: [String]) throws(DictionaryStoreError) {
        do {
            guard !words.isEmpty else { return try removeRefusalRecord() }
            try PrivateFile.write(JSONEncoder().encode(words), to: refusalRecord)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Throws away the tally and every refusal, in memory and on disk.
    private func forgetSightings() throws(DictionaryStoreError) {
        ledger = SightingLedger()
        do { try removeRefusalRecord() } catch { throw .couldNotWrite }
    }

    /// Deletes the refusal record if it is there.
    private func removeRefusalRecord() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: refusalRecord.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: refusalRecord)
    }

    // MARK: - The file

    /// Reads the file, setting an unreadable one aside so the next write cannot replace the only copy.
    private func load() -> [DictionaryEntry] {
        cache.load() ?? []
    }

    /// Writes the whole list atomically, or removes the file when nothing is left to keep.
    private func persist(_ entries: [DictionaryEntry]) throws(DictionaryStoreError) {
        do {
            guard !entries.isEmpty else {
                try removeFile()
                cache.remember(nil)
                return
            }
            try PrivateFile.write(JSONEncoder().encode(entries), to: file)
            cache.remember(entries)
        } catch {
            cache.forget()
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
