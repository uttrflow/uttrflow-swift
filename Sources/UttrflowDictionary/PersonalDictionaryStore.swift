public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONEncoder

/// The words this user says that a general model would not expect. See `Docs/app-dictionary-store.md`.
public actor PersonalDictionaryStore {
    /// The maximum number of inferred entries retained alongside user and shipped words.
    public static let maximumInferredEntries = 256
    /// The most deleted spellings refused at once; past it the oldest refusal lapses.
    public static let maximumRefusedWords = SightingLedger.maximumRefused
    /// The file, injected so a test writes into a temporary directory rather than a real dictionary.
    private let file: URL
    private let encryptedStore: EncryptedStore?

    /// The file's decoded contents, reread only when the file changed on disk.
    var cache: CachedStoredList<[DictionaryEntry]>

    /// The dictionary arranged by sound, and the cache generation it was built from.
    private var cachedIndex: (generation: Int, index: PhoneticIndex)?
    /// The words offered in one application arranged by sound, kept for the application last asked about.
    private var cachedScopedIndex: (generation: Int, application: String?, index: PhoneticIndex)?

    /// Terms seen and said but not yet on enough days to keep, and the words deleted; read from disk on first use.
    private var ledger: SightingLedger?
    /// Where pending sightings outlive a quit; without it they are counted in memory only.
    private let sightings: SightingMemory?

    public init(
        file: URL = PersonalDictionaryStore.defaultFile(), encryptedStore: EncryptedStore? = nil,
        sightings: SightingMemory? = nil
    ) {
        self.file = file
        self.encryptedStore = encryptedStore
        self.sightings = sightings
        self.cache = CachedStoredList(file: file) { url in
            encryptedStore.map { LocalStore.read([DictionaryEntry].self, from: url, encryptedBy: $0) }
                ?? LocalStore.read([DictionaryEntry].self, from: url)
        }
    }

    /// Where the dictionary lives by default; versioned in the name so a new shape can sit beside it.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStoreEntry.personalDictionary.location(in: directory)
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

    /// The words offered where `application` is in front, arranged by sound; every word when none is confined.
    public func index(in application: String?) -> PhoneticIndex {
        let entries = load()
        guard entries.contains(where: { !$0.applications.isEmpty }) else { return index() }
        let key = application.map(ApplicationKey.of)
        if let cachedScopedIndex, cachedScopedIndex.generation == cache.generation,
            cachedScopedIndex.application == key
        {
            return cachedScopedIndex.index
        }
        let built = PhoneticIndex(entries: entries.filter { $0.applies(in: application) })
        cachedScopedIndex = (cache.generation, key, built)
        return built
    }

    // MARK: - Writing

    /// Teaches the dictionary a word, replacing any entry that spells it the same way.
    @discardableResult
    public func add(_ entry: DictionaryEntry) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let entry = entry.inLatinScript
        if let refusal = PhoneticIndex.refusal(for: entry) {
            throw refusal
        }
        let spelling = entry.spellingKey
        return try persist(load().filter { $0.id != entry.id && $0.spellingKey != spelling } + [entry])
    }

    /// Replaces the list with what `merge` derives from it in one actor step, returning what the bound kept.
    @discardableResult
    public func replaceAll<Outcome: Sendable>(
        _ merge: @Sendable ([DictionaryEntry]) -> (entries: [DictionaryEntry], outcome: Outcome)
    ) throws(DictionaryStoreError) -> (kept: [DictionaryEntry], outcome: Outcome) {
        let derived = merge(load())
        let entries = derived.entries.map(\.inLatinScript)
        for entry in entries {
            if let refusal = PhoneticIndex.refusal(for: entry) {
                throw refusal
            }
        }
        let kept = try persist(entries)
        cachedIndex = nil
        return (kept, derived.outcome)
    }

    /// Writes what the user typed in as a word of their own, `pronunciation` being the editor's comma-separated field. See `Docs/app-dictionary-store.md`.
    @discardableResult
    public func add(
        word: String, pronunciation: String, at moment: Date, applications: [String] = []
    ) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let entry = try Self.typedEntry(
            word: word, pronunciation: pronunciation, at: moment, applications: applications)
        guard !load().contains(where: { $0.spellingKey == entry.spellingKey }) else {
            throw .wordAlreadyKnown
        }
        return try add(entry)
    }

    /// The new word the editor's two fields describe, in Latin letters, or why it cannot be kept; every typed word passes this one rule.
    public static func typedEntry(
        word: String, pronunciation: String, at moment: Date, applications: [String] = []
    ) throws(DictionaryStoreError) -> DictionaryEntry {
        let typed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { throw .wordIsEmpty }
        let entry = DictionaryEntry(
            word: typed, pronunciations: DictionaryEntry.pronunciations(inField: pronunciation),
            origin: .added, firstSeen: moment, applications: applications
        ).inLatinScript
        if let refusal = PhoneticIndex.refusal(for: entry) { throw refusal }
        return entry
    }

    /// Respells an entry as the user typed it, keeping its identity and counters, and drops any other entry of that spelling.
    @discardableResult
    public func replace(
        _ id: UUID, word: String, pronunciation: String, applications: [String]
    ) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let typed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { throw .wordIsEmpty }
        guard let existing = load().first(where: { $0.id == id }) else { return load() }
        return try add(
            DictionaryEntry(
                id: id, word: typed, pronunciations: DictionaryEntry.pronunciations(inField: pronunciation),
                origin: .added,
                firstSeen: existing.firstSeen, timesUsed: existing.timesUsed,
                timesReverted: existing.timesReverted, applications: applications))
    }

    /// Folds one spelling of a word into another: the kept entry takes both counters and the other goes.
    @discardableResult
    public func merge(
        keeping kept: UUID, absorbing absorbed: UUID
    ) throws(DictionaryStoreError) -> DictionaryEntry? {
        let entries = load()
        guard kept != absorbed,
            var keeper = entries.first(where: { $0.id == kept }),
            let other = entries.first(where: { $0.id == absorbed }),
            keeper.spellingKey == other.spellingKey
        else { return nil }
        keeper.timesUsed = DictionaryEntry.clamped(keeper.timesUsed + other.timesUsed)
        keeper.timesReverted = DictionaryEntry.clamped(keeper.timesReverted + other.timesReverted)
        let merged = keeper
        try persist(entries.compactMap { $0.id == absorbed ? nil : $0.id == kept ? merged : $0 })
        return merged
    }

    /// Offers shipped words once until a full reset; individual deletions stay deleted.
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
    private struct SeedRecord: Codable, Sendable {
        let version: Int
        let offered: [String]?
    }

    /// A missing record is new; an unreadable one, or one set aside as unreadable, is not evidence that a deleted word may return.
    private func offeredSpellings() throws(DictionaryStoreError) -> Set<String> {
        let record: SeedRecord
        switch readRecord(SeedRecord.self, from: seedRecord) {
        case .missing:
            guard !LocalStore.hasSetAside(seedRecord) else { throw .couldNotReadSeedRecord }
            return []
        case .unsupportedVersion:
            throw .couldNotReadSeedRecord
        case .unreadable: throw .couldNotReadSeedRecord
        case .read(let read), .recovered(let read, _, _, _, _): record = read
        }
        guard record.version >= 0 else { throw .couldNotReadSeedRecord }
        if let offered = record.offered { return Set(offered.map { $0.lowercased() }) }
        // A record written before spellings were listed names only a version, and version 1 was this list.
        return record.version >= 1 ? ShippedWords.versionOneSpellings : []
    }

    /// Notes every shipped spelling offered so far, which is what stops a deleted word returning.
    private func recordOffered(_ offered: Set<String>) throws(DictionaryStoreError) {
        let record = SeedRecord(version: ShippedWords.version, offered: offered.sorted())
        do {
            try writeRecord(record, to: seedRecord)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Forgets one word; an identifier that is not there is not an error.
    @discardableResult
    public func remove(_ id: UUID) async throws(DictionaryStoreError) -> [DictionaryEntry] {
        try await remove(Set([id]))
    }

    /// Forgets every named word and refuses each one, with one write of each record.
    @discardableResult
    public func remove(_ ids: Set<UUID>) async throws(DictionaryStoreError) -> [DictionaryEntry] {
        let existing = load()
        let gone = existing.filter { ids.contains($0.id) }
        let kept = existing.filter { !ids.contains($0.id) }
        // A deleted word must not simply be counted up again, whoever first put it there.
        var cancelled: [EvidenceRow] = []
        if !gone.isEmpty {
            var tally = await sightingLedger()
            for entry in gone { cancelled += tally.refuse(entry.word) }
            ledger = tally
            try recordRefusals(tally.refusals)
        }
        try persist(kept)
        try await remember(cancelled)
        return kept
    }

    /// Forgets every word, the user's own included; ``removeLearned()`` is almost always the one meant.
    public func removeEverything() async throws(DictionaryStoreError) {
        try await forgetEverything()
        try persist([])
        do {
            if FileManager.default.fileExists(atPath: seedRecord.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: seedRecord)
            }
            try LocalStore.removeSetAside(file)
        } catch {
            throw .couldNotWrite
        }
    }

    /// The spellings deleted words are refused under, newest first, as the Dictionary page lists them.
    public func refusedWords() async -> [String] {
        await sightingLedger().refusals.reversed()
    }

    /// Lets a refused spelling be learned again, removing it from the ledger and the record.
    public func allowAgain(_ word: String) async throws(DictionaryStoreError) {
        var tally = await sightingLedger()
        guard tally.allow(word) else { return }
        try recordRefusals(tally.refusals)
        ledger = tally
    }

    /// Adds refusals carried from another Mac after this one's own, oldest first, so past the bound the oldest lapse.
    public func importRefusals(_ words: [String]) async throws(DictionaryStoreError) -> RefusalImport {
        var tally = await sightingLedger()
        let before = Set(tally.refusals.map { $0.lowercased() })
        var incoming: [String] = []
        var seen = before
        for word in words where seen.insert(word.lowercased()).inserted { incoming.append(word) }
        guard !incoming.isEmpty else { return RefusalImport(added: 0, lapsed: 0) }
        // Only the newest bound's worth can survive, so older ones are never refused just to lapse at once.
        let kept = incoming.suffix(Self.maximumRefusedWords)
        var cancelled: [EvidenceRow] = []
        for word in kept { cancelled += tally.refuse(word) }
        try recordRefusals(tally.refusals)
        ledger = tally
        // A pending count left on disk is refused again when a relaunch loads the record, so this write may fail.
        try? await remember(cancelled)
        let after = Set(tally.refusals.map { $0.lowercased() })
        return RefusalImport(
            added: after.subtracting(before).count, lapsed: before.count + incoming.count - after.count)
    }

    /// Removes every inferred word through the batch `remove`, so each is refused, and clears pending sightings.
    @discardableResult
    public func removeLearned() async throws(DictionaryStoreError) -> [DictionaryEntry] {
        var tally = await sightingLedger()
        let cancelled = tally.clearPending()
        ledger = tally
        try await remember(cancelled)
        // A shipped word was inferred from nothing, so there is nothing about it to forget.
        let inferred = load().filter { $0.origin != .added && $0.origin != .shipped }
        return try await remove(Set(inferred.map(\.id)))
    }

    /// Learns from a dictation; `heard` is the raw transcript, `typed` lines read for sightings only. See `Docs/app-dictionary.md`.
    @discardableResult
    public func learn(
        heard: String, wrote: String, seeing context: AppContext, typed: [String] = [], at moment: Date
    ) async throws(DictionaryStoreError) -> [DictionaryEntry] {
        var tally = await sightingLedger()
        let existing = load()
        // What is already held, so neither path adds a second row or reaches the replacing `add`.
        var known = Set(existing.map(\.spellingKey))
        var learnt: [DictionaryEntry] = []

        if let corrected = LearnableWords.corrected(over: context.selectedText, wrote: wrote),
            !tally.isRefused(corrected),
            known.insert(DictionaryEntry.spellingKey(for: corrected)).inserted
        {
            learnt.append(DictionaryEntry(word: corrected, origin: .learned, firstSeen: moment))
        }

        // Filtered before the tally, so a word already held stops being counted rather than counted on.
        let seen = LearnableWords.seenAndSaid(heard: heard, seeing: context, typed: typed)
            .filter { !known.contains(DictionaryEntry.spellingKey(for: $0)) }
        let counted = tally.record(seen, on: EvidenceRow.day(of: moment))
        learnt += counted.learnt.map { DictionaryEntry(word: $0, origin: .observed, firstSeen: moment) }
        ledger = tally
        try await remember(counted.rows, at: moment)

        learnt = learnt.map(\.inLatinScript)
        guard !learnt.isEmpty else { return [] }
        let bounded = try persist(existing + learnt)
        return learnt.filter { entry in bounded.contains(where: { $0.id == entry.id }) }
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

    /// Notes that the user undid a dictation this entry was applied to; a provisional word is removed and refused.
    @discardableResult
    public func recordRevert(of id: UUID) async throws(DictionaryStoreError) -> DictionaryEntry? {
        let wasProvisional = load().first { $0.id == id }?.isProvisional ?? false
        let reverted = try update(id) { $0.timesReverted = DictionaryEntry.clamped($0.timesReverted + 1) }
        if wasProvisional { try await remove(id) }
        return reverted
    }

    /// Clears a retired entry's undo count, keeping its uses. See `Docs/app-dictionary-store.md`.
    @discardableResult
    public func restore(_ id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try restore(Set([id])).first
    }

    /// Clears every named entry's undo count with one write; an identifier that is not there changes nothing.
    @discardableResult
    public func restore(_ ids: Set<UUID>) throws(DictionaryStoreError) -> [DictionaryEntry] {
        try update(ids) { $0.timesReverted = 0 }
    }

    /// Respells every stored Devanagari word in Latin letters once, answering each change as before and after.
    @discardableResult
    public func respellInLatinScript()
        throws(DictionaryStoreError) -> [(before: DictionaryEntry, after: DictionaryEntry)]
    {
        let entries = load()
        let changes = entries.map { ($0, $0.inLatinScript) }.filter { $0.0 != $0.1 }
        guard !changes.isEmpty else { return [] }
        try persist(entries.map(\.inLatinScript))
        return changes.map { (before: $0.0, after: $0.1) }
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

    /// The ledger, starting from the refusals and pending sightings on disk the first time it is needed.
    private func sightingLedger() async -> SightingLedger {
        if let ledger { return ledger }
        var rows: [EvidenceRow] = []
        var digest: @Sendable (String) -> String? = { $0 }
        if let sightings {
            rows = await sightings.rows(at: Date())
            digest = sightings.digest
        }
        // Another call may have loaded it while this one waited.
        if let ledger { return ledger }
        let refusals = storedRefusals()
        try? encryptedStore?.markLegacyMigrationComplete(for: .dictionaryRecords)
        let loaded = SightingLedger(refusing: refusals, remembering: rows, digest: digest)
        ledger = loaded
        return loaded
    }

    /// Appends sighting rows to the evidence ledger; an unreadable ledger refuses rather than overwrite it.
    private func remember(_ rows: [EvidenceRow], at moment: Date = Date()) async throws(DictionaryStoreError)
    {
        guard let sightings, !rows.isEmpty else { return }
        do { try await sightings.append(rows, at: moment) } catch { throw .couldNotWrite }
    }

    /// The refusals a previous run wrote down; a missing or unreadable record refuses nothing.
    private func storedRefusals() -> [String] {
        readRecord([String].self, from: refusalRecord).value ?? []
    }

    /// Writes the refusals down, or removes the record when none is left.
    private func recordRefusals(_ words: [String]) throws(DictionaryStoreError) {
        do {
            guard !words.isEmpty else { return try removeRefusalRecord() }
            try writeRecord(words, to: refusalRecord)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Throws away pending counts and every refusal, in memory and on disk.
    private func forgetEverything() async throws(DictionaryStoreError) {
        var tally = await sightingLedger()
        let cancelled = tally.forgetEverything()
        ledger = tally
        do { try removeRefusalRecord() } catch { throw .couldNotWrite }
        try await remember(cancelled)
    }

    /// Deletes the refusal record if it is there.
    private func removeRefusalRecord() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: refusalRecord.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: refusalRecord)
    }

    // MARK: - The file

    /// Reads a sidecar record the way the list is read, so a sealed list never sits beside a plaintext record.
    private func readRecord<Value: Codable & Sendable>(
        _ type: Value.Type, from url: URL
    ) -> StoredList<Value> {
        encryptedStore.map { LocalStore.read(type, from: url, encryptedBy: $0) }
            ?? LocalStore.read(type, from: url)
    }

    /// Writes a sidecar record sealed whenever the list is; every caller has read it first, which migrates plaintext.
    private func writeRecord<Value: Codable & Sendable>(_ value: Value, to url: URL) throws {
        guard let encryptedStore else { return try PrivateFile.write(JSONEncoder().encode(value), to: url) }
        try encryptedStore.write(value, to: url)
    }

    /// Reads the file, setting an unreadable one aside so the next write cannot replace the only copy.
    private func load() -> [DictionaryEntry] {
        cache.load() ?? []
    }

    /// Writes the list within the inferred bound atomically, or removes the file when nothing is left; returns what it kept.
    @discardableResult
    private func persist(_ unbounded: [DictionaryEntry]) throws(DictionaryStoreError) -> [DictionaryEntry] {
        guard !cache.isUnreadable else { throw .couldNotWrite }
        let entries = Self.boundedEntries(unbounded)
        do {
            guard !entries.isEmpty else {
                try removeFile()
                cache.remember(nil)
                return entries
            }
            if let encryptedStore {
                try encryptedStore.write(entries, to: file)
            } else {
                try PrivateFile.write(JSONEncoder().encode(entries), to: file)
            }
            cache.remember(entries)
        } catch {
            cache.forget()
            throw .couldNotWrite
        }
        return entries
    }

    /// Keeps all trusted origins and the strongest, most recent inferred entries within the bound.
    private static func boundedEntries(_ entries: [DictionaryEntry]) -> [DictionaryEntry] {
        let inferred = entries.filter { $0.origin == .learned || $0.origin == .observed }
        guard inferred.count > maximumInferredEntries else { return entries }
        let retained = Set(
            inferred.sorted {
                if $0.netUses != $1.netUses { return $0.netUses > $1.netUses }
                if $0.firstSeen != $1.firstSeen { return $0.firstSeen > $1.firstSeen }
                return $0.word.localizedStandardCompare($1.word) == .orderedAscending
            }.prefix(maximumInferredEntries).map(\.id))
        return entries.filter {
            ($0.origin != .learned && $0.origin != .observed) || retained.contains($0.id)
        }
    }

    /// Deletes the file if it is there; nothing to delete is success, not a failure.
    private func removeFile() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: file)
    }
}

/// What importing refusals changed: spellings newly refused, and refusals that lapsed past the bound.
public struct RefusalImport: Sendable, Equatable {
    public let added: Int
    public let lapsed: Int
}
