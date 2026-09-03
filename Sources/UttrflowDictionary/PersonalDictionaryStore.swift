public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

/// The words this user says that a general model would not expect, kept on this Mac
/// between launches.
///
/// Its own file under Application Support, beside the history rather than inside it:
/// the two age differently, are reset by different buttons, and a user who clears their
/// history must not thereby forget how to spell their colleagues' names.
///
/// An actor, for the reason the history store gives — the writers are dictations that
/// have already finished and the readers are windows, so waiting should be a suspension
/// and not a blocked main thread.
///
/// It diverges from the history store in one deliberate way: it caches. The history is
/// read when a window is drawn, so re-reading the file is cheap enough to buy the
/// certainty that the file is the only truth. This is read on the *hot path* — once
/// before every dictation and again after it — and rebuilding a phonetic index from
/// disk each time would put the whole dictionary back into a cost the index exists to
/// remove. So the index is built once and kept until a write invalidates it. The price
/// is that a user who edits the file in the Finder while the app is running is not seen
/// until the next write, which is a trade the history store could not make and this one
/// can.
public actor PersonalDictionaryStore {
    /// The file. Injected so a test writes into a temporary directory and never into the
    /// dictionary of whoever is running it.
    private let file: URL

    /// Built on demand and thrown away by every write.
    ///
    /// Not `[DictionaryEntry]`, because the entries are not what the hot path wants —
    /// the index is, and caching the raw list would leave the expensive half to be
    /// redone anyway.
    private var cachedIndex: PhoneticIndex?

    /// Terms noticed on screen and said aloud, but not yet seen often enough to keep.
    ///
    /// Held here rather than beside the file, and never written to it. Two reasons, and
    /// the first is privacy: these words came off the user's screen and most will never
    /// become entries, so a file of them would be a record of what they had open that no
    /// page shows and no button clears. The second is the reset — this is the app's
    /// inference like any other, and being inside the actor that owns
    /// ``removeLearned()`` is what makes it impossible to forget to throw it away.
    private var sightings = SightingLedger()

    public init(file: URL = PersonalDictionaryStore.defaultFile()) {
        self.file = file
    }

    /// Where the dictionary lives when the app has not been told otherwise.
    ///
    /// Versioned in the name so that a shape too different to read field by field can
    /// one day be introduced beside this one rather than on top of it.
    ///
    /// - Parameter directory: The container to put Uttrflow's folder in. Nothing but a
    ///   test has a reason to pass one.
    /// - Returns: The file the dictionary is read from and written to.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("dictionary.v1.json", in: directory)
    }

    // MARK: - Reading

    /// Every word, in the order it was added — including the ones that have retired
    /// themselves.
    ///
    /// Retired entries are listed on purpose. They are excluded from the *lookup*, so
    /// they can do no more harm, but a user who is told a word has stopped being used
    /// and cannot then see it has been told nothing useful.
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

    /// The words worth conditioning the recogniser with before it decodes.
    ///
    /// Forwards to ``WorkingSet/words(from:limit:now:favouring:)``; the ranking lives
    /// there so it can be tested without a disk.
    public func workingSet(
        limit: Int = WorkingSet.defaultLimit,
        now: Date,
        favouring context: AppContext = .unknown
    ) -> [String] {
        WorkingSet.words(from: load(), limit: limit, now: now, favouring: context)
    }

    // MARK: - Writing

    /// Teaches the dictionary a word, and answers with the dictionary as it now stands.
    ///
    /// Replaces any entry with the same identifier, and any *other* entry spelling the
    /// same word — case-insensitively, because "Kubectl" and "kubectl" are one word to
    /// the user and two rows in a settings list is a bug they can see. The newcomer's
    /// spelling wins, since it is the one they just asked for.
    ///
    /// Answers with the list rather than nothing so a caller cannot draw a window from a
    /// copy it forgot to refresh.
    @discardableResult
    public func add(_ entry: DictionaryEntry) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let spelling = entry.word.lowercased()
        let kept =
            load().filter { $0.id != entry.id && $0.word.lowercased() != spelling } + [entry]
        try persist(kept)
        return kept
    }

    /// Writes what the user typed into the editor as a word they added themselves.
    ///
    /// Here rather than at the call site so that the trimming, the empty-pronunciation
    /// rule and the origin are decided once. A blank pronunciation is stored as absent,
    /// not as an empty string: ``DictionaryEntry/soundsLike`` falls back to the spelling
    /// when it is `nil`, and an empty string would index the word under no sound at all
    /// — it would never be found, and nothing would say why.
    ///
    /// - Throws: ``DictionaryStoreError/wordIsEmpty`` when there is no spelling, and
    ///   ``DictionaryStoreError/wordAlreadyKnown`` when the dictionary already holds it.
    ///   The editor refuses both before the button is live — but from the list it last
    ///   drew, and that list can go stale *while the editor is open* now that a dictation
    ///   finishing in another app can teach the dictionary a word. Checked here as well,
    ///   because only here is the answer current.
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

    /// Forgets one word, and answers with what is left.
    ///
    /// An identifier that is not there is not an error: the caller asked for it to be
    /// gone, and it is.
    @discardableResult
    public func remove(_ id: UUID) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let existing = load()
        let kept = existing.filter { $0.id != id }
        // A word Uttrflow worked out for itself and the user then deleted must not come
        // back. It is still in the window title and still being said, so clearing the
        // tally alone would simply count it up to the threshold again — three dictations
        // later the deleted word reappears, which is the app arguing with the person
        // using it.
        //
        // Only the words it inferred. A word the user typed in and then deleted is theirs
        // to change their mind about, and nothing would re-learn it anyway.
        if let gone = existing.first(where: { $0.id == id }), gone.origin != .added {
            sightings.refuse(gone.word)
        }
        try persist(kept)
        return kept
    }

    /// Forgets every word, including the ones the user typed in themselves.
    ///
    /// The blunt instrument. ``removeLearned()`` is almost always the one they wanted.
    public func removeEverything() throws(DictionaryStoreError) {
        sightings.forgetEverything()
        try persist([])
    }

    /// Forgets everything Uttrflow worked out for itself, and keeps everything the user
    /// taught it by hand.
    ///
    /// This is the operation the rest of the design is insured by. A dictionary that
    /// learns is a dictionary that can learn the wrong thing — a mis-heard name accepted
    /// once and reinforced, a colleague's surname bound to a typo — and the honest
    /// answer to a poisoned dictionary is to throw the inferences away. Throwing away
    /// the user's own words at the same time would make the fix cost more than the
    /// fault, and they would stop using it.
    ///
    /// Both ``WordOrigin/learned`` and ``WordOrigin/observed`` go, because both are the
    /// app's inference and the user cannot be expected to know which of the two
    /// mechanisms guessed wrong. Only ``WordOrigin/added`` — words they typed in
    /// deliberately — survives.
    ///
    /// It is also why the dictionary is not capped in size the way the history is. The
    /// history trims itself silently because nobody chose those records; here, a silent
    /// trim would delete words a user deliberately taught the app. This is the reset
    /// instead, and it is one the user asks for and can predict.
    @discardableResult
    public func removeLearned() throws(DictionaryStoreError) -> [DictionaryEntry] {
        // The half-counted evidence goes with the entries. A word that appeared one
        // dictation after the user asked Uttrflow to forget what it had worked out would
        // make a liar of the button.
        sightings.forgetEverything()
        let kept = load().filter { $0.origin == .added }
        try persist(kept)
        return kept
    }

    /// Learns what a dictation that landed had to teach, and answers with any word it
    /// kept.
    ///
    /// The two automatic paths into the dictionary, and the only two. Both are argued in
    /// ``LearnableWords``, which is where the thresholds and their reasons live; this
    /// method is the part that needs a disk and a memory of previous dictations, and it
    /// is deliberately the only part.
    ///
    /// Called after the words are on the user's screen and never before. A word earns
    /// its place by *surviving* a dictation, and a dictation that failed to insert
    /// taught nobody anything.
    ///
    /// Nothing is written when nothing is learnt, which is nearly every dictation. That
    /// guard is what keeps the feature off the disk rather than merely off the hot path.
    ///
    /// - Parameters:
    ///   - heard: exactly what the recogniser produced, before anything rewrote it.
    ///     The raw transcript and not the finished text, because the question this path
    ///     asks is what the user *said*, and by the end of the pipeline the tidier and
    ///     the snippets have both had a turn at changing it.
    ///   - wrote: what actually landed on their screen.
    ///   - context: what was in front of them while they spoke.
    ///   - moment: when, kept out of the store for the reason every other clock here is.
    /// - Returns: The entries this dictation added, in the order they were learnt.
    ///   Empty is the expected answer.
    /// - Throws: ``DictionaryStoreError/couldNotWrite`` when the file would not take the
    ///   new words. The dictation is already over, so the caller drops this — a lesson
    ///   is worth less than a notice about one.
    @discardableResult
    public func learn(
        heard: String, wrote: String, seeing context: AppContext, at moment: Date
    ) throws(DictionaryStoreError) -> [DictionaryEntry] {
        let existing = load()
        // What the dictionary already holds, so neither path can add a second row for a
        // word that is there — and in particular cannot reach ``add(_:)``, which replaces
        // an entry of the same spelling and would reset the counters of a word the user
        // typed in themselves.
        var known = Set(existing.map { $0.word.lowercased() })
        var learnt: [DictionaryEntry] = []

        if let corrected = LearnableWords.corrected(over: context.selectedText, wrote: wrote),
            known.insert(corrected.lowercased()).inserted
        {
            learnt.append(DictionaryEntry(word: corrected, origin: .learned, firstSeen: moment))
        }

        // Filtered before the tally and not after it, so that a word the user has
        // already got stops being counted at all rather than being counted forever and
        // discarded at the end.
        let seen = LearnableWords.seenAndSaid(heard: heard, seeing: context)
            .filter { !known.contains($0.lowercased()) }
        learnt += sightings.record(seen).map {
            DictionaryEntry(word: $0, origin: .observed, firstSeen: moment)
        }

        guard !learnt.isEmpty else { return [] }
        try persist(existing + learnt)
        return learnt
    }

    /// Notes that an entry was applied to a dictation.
    ///
    /// Answers with the entry as it now stands so that a caller can see the moment it
    /// retires itself, rather than discovering it from a lookup that has quietly stopped
    /// returning it. `nil` when there is no such entry, which is what a caller holding a
    /// stale list should be told.
    @discardableResult
    public func recordUse(of id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try update(id) { $0.timesUsed += 1 }
    }

    /// Notes that the user undid a dictation this entry was applied to.
    ///
    /// The only honest evidence that an entry is wrong, and the input to
    /// ``DictionaryEntry/isTrustworthy``.
    @discardableResult
    public func recordRevert(of id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try update(id) { $0.timesReverted += 1 }
    }

    /// Gives a retired entry a clean slate, at the user's explicit request.
    ///
    /// Clears the undo count rather than nudging it back below the threshold, because
    /// the counters are evidence and evidence the user has overruled is not evidence any
    /// more. Leaving one undo behind would retire the word again after a single further
    /// mistake, which is not what "Restore" says on the button.
    ///
    /// ``DictionaryEntry/timesUsed`` deliberately survives: how often a word has been
    /// applied is a fact about the past that the user has not disputed. It also gives the
    /// restored word a longer leash rather than a shorter one — ``isTrustworthy`` is a
    /// ratio, so a word restored at twenty uses can be undone nine times before it
    /// retires again, where one reset to zero would be back under the three-use grace
    /// period and could retire on its fourth mistake.
    @discardableResult
    public func restore(_ id: UUID) throws(DictionaryStoreError) -> DictionaryEntry? {
        try update(id) { $0.timesReverted = 0 }
    }

    /// One place where an entry is found, changed and written back, so that the two
    /// counters cannot drift into two different ideas of what a missing entry means.
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
    ///
    /// Absent, unreadable, truncated, hand-edited, or written by a build that knew a
    /// different shape — to a user those all mean the same thing, which is that the app
    /// should still open. A dictionary that has forgotten everything makes dictation
    /// slightly worse; a dictionary that refuses to load makes it impossible.
    private func load() -> [DictionaryEntry] {
        guard let data = try? Data(contentsOf: file),
            let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
        else { return [] }
        return entries
    }

    /// Writes the whole list, or removes the file when nothing is left to keep.
    ///
    /// Atomically, so that a crash or a full disk cannot leave behind the truncated file
    /// ``load()`` would then have to throw away. Removing rather than writing an empty
    /// array means an emptied dictionary leaves nothing of the user's on disk at all.
    ///
    /// The cache is dropped before the write is attempted, not after it succeeds: a
    /// failed write leaves the disk holding the old list, and an index rebuilt from that
    /// is right either way. Dropping it only on success would be one more state to be
    /// wrong about.
    private func persist(_ entries: [DictionaryEntry]) throws(DictionaryStoreError) {
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

    /// Deletes the file if it is there. Nothing to delete is success, not a failure.
    private func removeFile() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: file)
    }
}
