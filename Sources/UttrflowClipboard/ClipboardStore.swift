import UttrflowCore
import CryptoKit

public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

/// Everything the user has copied, kept on this Mac between launches.
///
/// Sibling to `DictationHistoryStore`, and different from it in exactly one way that
/// matters: this one holds its list in memory as well as on disk.
///
/// The history store deliberately does not, and gives a good reason — the file is the
/// single source of truth, and a copy beside it can disagree with a user who deleted it
/// in the Finder. That reasoning holds because the history is read when a window is
/// drawn, which happens rarely. This list is read on ⇧⌘V, which is the whole product:
/// the panel is opened dozens of times a day, and the user is looking at the screen
/// waiting for it. Decoding five hundred records from JSON on that path buys certainty
/// nobody asked for at a cost everybody sees. So the file is read once, lazily, and
/// every read after that is a filter over an array already in memory — no I/O at all,
/// and no `await` that can block on a disk. Writes go to memory and to disk together,
/// so the two never drift while the app is running.
///
/// An actor rather than a lock, for the reason the history store gives: nothing here is
/// real-time, a write is a whole-file rewrite, and the thread that asks most often is
/// the main one. An actor turns waiting into suspension.
public actor ClipboardStore {
    /// Every bound this store applies, in one value: how many records each pool of
    /// clips may hold, how much memory, how long, and the size of the largest single clip
    /// it will keep at all.
    ///
    /// A build-time shape rather than a user setting — see ``ClipboardBudget``. The two
    /// numbers that used to live here as `defaultCapacity` and `defaultBudget` are inside
    /// it, alongside the ones they were missing: a window per pool, a memory quota per
    /// pool, and ``ClipboardBudget/largestClip``, which is the only one of them that can
    /// stop the list growing without bound.
    public static let defaultBudget = ClipboardBudget.standard

    /// The file. Injected so a test writes into a temporary directory and never into
    /// the clipboard of whoever is running it.
    private let file: URL

    /// What each pool may cost, and for how long.
    private let budget: ClipboardBudget

    /// The list as it now stands, newest first, or `nil` before the file has been read.
    ///
    /// Optional rather than empty so that "not loaded yet" and "loaded and empty" are
    /// different states. Without that, an empty clipboard would re-read the file on
    /// every panel open — the one case where the cache is most obviously pointless.
    /// The history, the saved clips, and the two of them as the one list everything above
    /// here reads. `nil` before the files have been read — optional rather than empty so
    /// that "not loaded yet" and "loaded and empty" are different states, without which an
    /// empty clipboard would re-read on every panel open.
    private var historyClips: [Clip]?
    private var savedClips: [Clip]?
    /// What the saved file is known to contain, as opposed to what is in memory.
    ///
    /// The two differ exactly once, and it is the case that made this necessary: a
    /// clipboard written before the split has its saved clips inside the history file, so
    /// after the first read `savedClips` already holds them and the saved file does not
    /// exist. Comparing the write against memory would then decide there was nothing to
    /// write, and the migration would never reach the disk.
    private var persistedSaved: [Clip]?
    private var wholeList: [Clip]?
    /// Whether this process has already reconciled the pictures folder; see
    /// ``sweepOnce(against:)``.
    private var hasSwept = false

    public init(
        file: URL = ClipboardStore.defaultFile(),
        budget: ClipboardBudget = ClipboardStore.defaultBudget
    ) {
        self.file = file
        self.budget = budget
    }

    /// Where the clipboard lives when the app has not been told otherwise.
    ///
    /// Versioned in the name so that a shape too different to read field by field can
    /// one day be introduced beside this one rather than on top of it.
    ///
    /// - Parameter directory: The container to put Uttrflow's folder in. Nothing but a
    ///   test has a reason to pass one.
    /// - Returns: The file the clipboard is read from and written to.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("clipboard.v1.json", in: directory)
    }

    // MARK: - Reading

    /// Everything still retained, newest first.
    ///
    /// This is the call ⇧⌘V waits on, and it does no I/O once the store has been read
    /// once: a filter and a `prefix` over an array already in memory.
    ///
    /// The window is applied here and not only where things are written, because the
    /// promise is about elapsed time and time passes while the app sits idle. When that
    /// drops something, the disk is caught up too — best-effort, because refusing to
    /// open the panel for a disk that refused a tidy-up would punish the user for
    /// something they cannot fix, and either way nothing they were told is gone comes
    /// back on screen.
    public func clips(keeping retention: ClipRetention) -> [Clip] {
        let stored = loaded()
        let kept = retained(stored, keeping: retention)
        if kept.count != stored.count { try? save(kept) }
        return kept
    }

    // MARK: - Writing

    /// Records a copy and answers with the clipboard as it now stands, newest first.
    ///
    /// Two things happen here that make the list usable.
    ///
    /// An empty or whitespace-only copy is refused outright, and silently. Nobody asked
    /// for it — an application wrote a stray newline to the clipboard — so there is
    /// nothing to report and nothing to record.
    ///
    /// A repeat of something already held moves that clip to the top rather than adding
    /// a second row. Without this, holding down ⌘C over the same value while switching
    /// windows fills the panel with one value, and the panel stops being scannable.
    /// What survives the move is everything the user did deliberately: the alias they
    /// typed, the category they filed it under, the pin. Only the identifier and those
    /// are inherited — the timestamp, the kind and the source come from the new copy,
    /// because it genuinely was copied again, just now, from somewhere.
    ///
    /// Answers with the list rather than nothing so a caller cannot draw a panel from a
    /// copy it forgot to refresh.
    @discardableResult
    public func record(
        _ clip: Clip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        // A picture has no text and is still worth keeping — the emptiness is the point.
        guard clip.image != nil || ClipContent.isWorthKeeping(clip.text) else {
            return retained(loaded(), keeping: retention)
        }
        // And a clip too large to be worth holding is refused here, before it is ever in
        // memory. This is the bound that actually stops the list growing: every rule
        // below assumes many small things and evicts *many*, and one copied log file is
        // one thing. It cost twice over — the bytes sat in the list for as long as the
        // list lived, and the whole file is rewritten atomically on every copy, so one
        // enormous clip made every later ⌘C an enormous write.
        //
        // Refused rather than truncated: half a log file is not a clip anybody wants, and
        // a history entry that silently differs from what was copied is worse than no
        // entry. What is lost is the row; the text is still on the system clipboard and
        // still pastes.
        guard budget.largestClip <= 0 || Self.weight(of: clip) <= budget.largestClip else {
            return retained(loaded(), keeping: retention)
        }

        let existing = loaded()
        // Two clips are the same thing when they carry the same thing. For text that is
        // the text; for a picture it is the bytes, compared by digest.
        //
        // Pictures used to be exempt: the only comparison was `text`, and every picture's
        // text is empty, so matching on it made every screenshot the same clip as the
        // last — the second replaced the first, its file was orphaned, and the surviving
        // row pointed at neither. Exempting them was the safe fix; comparing the right
        // thing is the correct one. A picture with no digest — one stored before this
        // existed — still never merges.
        let previous = previous(for: clip, in: existing)
        let arrival = previous.map { inheriting($0, from: clip) } ?? clip

        // Prepended, not sorted in. Order is arrival order, because the clock belongs to
        // the caller and a machine whose clock moved must not be able to shuffle what
        // the user is shown.
        let displaced = previous.map { [$0.id] } ?? []
        let updated = [arrival] + existing.filter { !displaced.contains($0.id) }
        let kept = retained(updated, keeping: retention)
        try save(kept)
        return kept
    }

    /// Records that a clip has just been reached for, so the eviction policy can see it.
    ///
    /// Called when a clip is pasted or put back on the clipboard — the two things a user
    /// does that mean "this one". Without it ``Clip/lastUsedAt`` would only ever be the
    /// arrival time and the policy would be least-recently-*copied* wearing an LRU name.
    ///
    /// Best-effort by design, and the one write here allowed to fail quietly: this is
    /// bookkeeping for a future eviction, and refusing somebody's paste because the note
    /// about it could not be filed would trade the thing they asked for against the
    /// record of it.
    @discardableResult
    public func markUsed(
        _ id: UUID, at moment: Date, keeping retention: ClipRetention
    ) -> [Clip] {
        var clips = loaded()
        guard let index = clips.firstIndex(where: { $0.id == id }) else {
            return retained(clips, keeping: retention)
        }
        clips[index] = clips[index].used(at: moment)
        let kept = retained(clips, keeping: retention)
        try? save(kept)
        return kept
    }

    /// Forgets one clip, and answers with what is left.
    ///
    /// An identifier that is not there is not an error: the caller asked for it to be
    /// gone, and it is.
    @discardableResult
    public func delete(
        _ id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let kept = retained(loaded().filter { $0.id != id }, keeping: retention)
        try save(kept)
        return kept
    }

    /// Forgets the history, and deliberately not what the user saved.
    ///
    /// "Clear clipboard" means the record of what you have copied. It cannot mean the
    /// things you named, filed and pinned so you could come back to them — those are the
    /// clips somebody would be most upset to lose and the ones they were least expecting
    /// this button to touch. It used to take them: `save([])` wrote an empty list, and an
    /// empty list is empty of everything.
    ///
    /// Deleting a saved clip is still possible and still one gesture — ``delete(_:keeping:)``
    /// on the row, which is the user pointing at the thing they mean.
    ///
    /// Reaches the disk inside this call rather than at the next write: a user who clears
    /// their clipboard and then quits must not find it still there.
    @discardableResult
    public func deleteEverything(
        keeping retention: ClipRetention
    ) throws(ClipboardStoreError)
        -> [Clip]
    {
        let saved = loaded().filter(\.isKept)
        try save(saved)
        return retained(saved, keeping: retention)
    }

    /// Removes every clip, pinned ones included.
    ///
    /// Distinct from ``deleteEverything(keeping:)``, and the difference is the whole
    /// point of both. "Clear clipboard" is a tidy-up and must spare what somebody named,
    /// filed and pinned. "Reset personalisation" says it puts Uttrflow back to a fresh
    /// install, and a fresh install has no clips of any kind — so this is the one call
    /// that takes them, and it exists separately so that neither promise can be made by
    /// accident from the other's button.
    ///
    /// It matters more than it looks: every finished dictation is written here as a
    /// second copy of the transcript, so a reset that spared this file left every word
    /// the user had ever spoken on the disk after telling them it was gone.
    public func forgetEverything() throws(ClipboardStoreError) {
        try save([])
    }

    /// Pins a clip, or unpins it.
    ///
    /// Pinning is one of the three things that make a clip kept, so this is also how a
    /// clip stops ageing out. It does not reorder anything: the store answers in arrival
    /// order and the panel decides where pinned rows are shown, because that is a
    /// presentation question and two answers to it would disagree.
    @discardableResult
    public func setPinned(
        _ isPinned: Bool, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { $0.isPinned = isPinned }
    }

    /// Gives a clip a handle the user can find it by, or takes it away.
    ///
    /// Passing `nil` removes the alias, which can make a clip unkept again — and an
    /// unkept clip is subject to the window and the cap from that moment. That is the
    /// user saying they no longer need it, so it is the right outcome, but it is the
    /// reason the retention rules are applied here rather than only on the way in.
    @discardableResult
    public func setAlias(
        _ alias: String?, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { $0.alias = alias }
    }

    /// D4 — replaces a clip's text, keeping everything the user chose about it.
    ///
    /// The only call here that rewrites what was copied, which is why it is separate from
    /// the three that merely label it. ``Clip/text`` is `let` on purpose — a clip is what
    /// was on the clipboard — so this builds a replacement carrying the same identity,
    /// alias, collection, pin and arrival time rather than mutating one in place. The
    /// identity matters: the row must not jump, and an undo must still find it.
    ///
    /// Everything a rebuild does not name reverts to a default, which is how this quietly
    /// reset ``Clip/timesCopied`` to one: tidying a clip the user reached for thirty times
    /// made it the cheapest thing in the history to evict. Nothing may be left out here.
    ///
    /// It does not touch ``Clip/richText``. A re-indent is about the plain form; the rich
    /// form is a different representation of the same clip and nothing here can tidy it.
    @discardableResult
    public func setText(
        _ text: String, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
            clip = Clip(
                id: clip.id, text: text, kind: clip.kind, copiedAt: clip.copiedAt,
                source: clip.source, origin: clip.origin, lastUsedAt: clip.lastUsedAt,
                language: clip.language, richText: clip.richText, image: clip.image,
                alias: clip.alias, category: clip.category, isPinned: clip.isPinned,
                timesCopied: clip.timesCopied)
        }
    }

    // MARK: - Pictures

    /// Where the pictures live: a folder beside the clipboard file.
    ///
    /// Beside rather than inside, because the clipboard is one JSON document rewritten
    /// whole on every copy and a picture must never be part of that write.
    public var imagesFolder: URL {
        file.deletingLastPathComponent().appending(path: "Images", directoryHint: .isDirectory)
    }

    /// K4 — records a noticed copy, writing its picture first when it has one.
    ///
    /// One call rather than two, so a clip can never be recorded pointing at a file that
    /// was not written. The order is deliberate: the picture goes down first, because a
    /// file with no clip is swept up later while a clip with no file is a broken row for
    /// ever.
    @discardableResult
    public func record(
        _ noticed: NoticedClip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        guard let picture = noticed.picture else {
            return try record(noticed.clip, keeping: retention)
        }
        // Hashed before it is written. A screenshot copied twice is the same clip, and
        // the second copy should cost a counter rather than another file on the disk —
        // which for a Retina screenshot is a megabyte saved every time somebody presses
        // ⌘C twice.
        let sha = ClipboardStore.digest(of: picture.data)
        if let previous = Self.previous(
            for: Clip(
                text: noticed.clip.text, kind: noticed.clip.kind,
                copiedAt: noticed.clip.copiedAt, origin: noticed.clip.origin,
                image: ClipImage(file: "", width: 0, height: 0, bytes: 0, sha: sha)),
            in: loaded()),
            let kept = previous.image
        {
            return try record(
                Clip(
                    id: noticed.clip.id, text: noticed.clip.text, kind: noticed.clip.kind,
                    copiedAt: noticed.clip.copiedAt, source: noticed.clip.source,
                    origin: noticed.clip.origin, lastUsedAt: noticed.clip.lastUsedAt,
                    language: noticed.clip.language, richText: noticed.clip.richText,
                    image: kept, alias: noticed.clip.alias, category: noticed.clip.category,
                    isPinned: noticed.clip.isPinned),
                keeping: retention)
        }
        let image = try keep(
            picture.data, forClip: noticed.clip.id, width: picture.width,
            height: picture.height, sha: sha)
        let clip = Clip(
            id: noticed.clip.id, text: noticed.clip.text, kind: noticed.clip.kind,
            copiedAt: noticed.clip.copiedAt, source: noticed.clip.source,
            origin: noticed.clip.origin, lastUsedAt: noticed.clip.lastUsedAt,
            language: noticed.clip.language, richText: noticed.clip.richText, image: image,
            alias: noticed.clip.alias, category: noticed.clip.category,
            isPinned: noticed.clip.isPinned)
        return try record(clip, keeping: retention)
    }

    /// Keeps a picture and returns what a row needs to draw it.
    ///
    /// Written before the clip is recorded, so a clip never refers to a file that is not
    /// there yet. The reverse — a file with no clip — is the harmless direction: it is
    /// swept up by ``forgetOrphanedImages()``.
    ///
    /// - Throws: ``ClipboardStoreError/couldNotWrite`` when the picture cannot be saved.
    ///   Deliberately not swallowed: a clip claiming a picture that was never written is
    ///   a broken row for ever, where a refused copy is one the user can simply repeat.
    public func keep(
        _ data: Data, forClip id: UUID, width: Int, height: Int, sha: String? = nil
    ) throws(ClipboardStoreError) -> ClipImage {
        let name = "\(id.uuidString).png"
        do {
            try FileManager.default.createDirectory(
                at: imagesFolder, withIntermediateDirectories: true)
            try data.write(to: imagesFolder.appending(path: name, directoryHint: .notDirectory))
        } catch {
            throw .couldNotWrite
        }
        return ClipImage(
            file: name, width: width, height: height, bytes: data.count,
            sha: sha ?? ClipboardStore.digest(of: data))
    }

    /// A picture's bytes, as a short hexadecimal digest.
    ///
    /// SHA-256 from CryptoKit, which ships with the system: no dependency, and no chance
    /// of two different screenshots being taken for one another. Truncated to sixteen
    /// bytes because this is a cache key rather than a signature — the file it names is
    /// beside it on the same disk, and a full digest doubles the size of every picture
    /// row in a file that is rewritten on every copy.
    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The bytes of a clip's picture, or `nil` when the file has gone.
    ///
    /// B8 — a picture can vanish underneath the app: the folder is on disk and disks are
    /// shared with the user. `nil` is the row's cue to say so rather than draw a blank.
    public func imageData(for image: ClipImage) -> Data? {
        try? Data(
            contentsOf: imagesFolder.appending(path: image.file, directoryHint: .notDirectory))
    }

    /// Deletes pictures no clip refers to any more.
    ///
    /// Called after the retention sweep, because that is the one place clips disappear
    /// without anybody asking for it — an image left behind by an aged-out clip is a file
    /// that would otherwise sit there for ever. Best-effort by design: a picture that
    /// cannot be deleted costs disk space, and refusing the whole write over it would
    /// cost the user their clipboard.
    public func forgetOrphanedImages() {
        let wanted = Set(loaded().compactMap(\.image?.file))
        let onDisk =
            (try? FileManager.default.contentsOfDirectory(
                at: imagesFolder, includingPropertiesForKeys: nil)) ?? []
        for file in onDisk where !wanted.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// E5, E6 — replaces a clip's note, keeping its plain form and everything else.
    ///
    /// Deliberately separate from ``setText(_:of:keeping:)``. That one rewrites what was
    /// copied; this one only ever touches the second representation, which is what makes
    /// E6's promise — the original plain text stays recoverable — structural rather than
    /// a thing anybody has to remember.
    ///
    /// A rebuild for the same reason, and so with the same obligation: every field is
    /// carried across by name, because one left out is one silently returned to its
    /// default.
    @discardableResult
    public func setRichText(
        _ richText: String?, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
            clip = Clip(
                id: clip.id, text: clip.text, kind: clip.kind, copiedAt: clip.copiedAt,
                source: clip.source, origin: clip.origin, lastUsedAt: clip.lastUsedAt,
                language: clip.language, richText: richText, image: clip.image,
                alias: clip.alias, category: clip.category, isPinned: clip.isPinned,
                timesCopied: clip.timesCopied)
        }
    }

    /// Files a clip into a collection, or takes it out of one.
    @discardableResult
    public func setCategory(
        _ category: String?, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { $0.category = category }
    }

    // MARK: - The rules

    /// Carries the deliberate parts of an existing clip onto the copy that has just
    /// replaced it. Copying the same value twice must never quietly un-name it.
    /// The clip this arrival is another copy of, if the history already holds it.
    static func previous(for clip: Clip, in existing: [Clip]) -> Clip? {
        // Only within the same list. A sentence dictated and the same sentence copied out
        // of a document are two clips, not one thing that happened twice: merging them
        // would move a row from one tab to the other and add to a count that is supposed
        // to mean "you reach for this often", which is the argument for keeping the two
        // streams apart in the first place.
        let sameList = existing.filter { $0.origin == clip.origin }
        if let sha = clip.image?.sha {
            return sameList.first { $0.image?.sha == sha }
        }
        guard clip.image == nil else { return nil }
        return sameList.first { $0.text == clip.text && $0.image == nil }
    }

    private func previous(for clip: Clip, in existing: [Clip]) -> Clip? {
        Self.previous(for: clip, in: existing)
    }

    private func inheriting(_ previous: Clip, from arrival: Clip) -> Clip {
        Clip(
            id: previous.id, text: arrival.text, kind: arrival.kind, copiedAt: arrival.copiedAt,
            source: arrival.source,
            // The same either way — ``previous(for:in:)`` only ever matches inside one
            // list — and named rather than defaulted, because leaving it out would let a
            // repeat quietly become a ⌘C.
            origin: previous.origin,
            // Copying something again is reaching for it, so the clock the eviction
            // policy reads moves too. Without this a value copied every morning would
            // still be ranked by the morning it first arrived.
            lastUsedAt: arrival.copiedAt,
            // Everything the arrival worked out about itself comes with it. This used to
            // drop all three, so copying the same thing twice quietly stripped it: a Swift
            // snippet lost its language chip on the second copy, and a formatted note lost
            // its formatting — the clip looked identical and had been hollowed out.
            //
            // The arrival's is right rather than the previous one's: it was detected from
            // the text being recorded now, and the pasteboard may be carrying a rich form
            // this time that it was not carrying before.
            language: arrival.language, richText: arrival.richText,
            // The picture that is already on disk, not the one just written: they are the
            // same bytes, and keeping the arrival's would strand the original file.
            image: previous.image ?? arrival.image,
            // And everything the *user* decided stays with the clip they decided it about.
            alias: previous.alias, category: previous.category, isPinned: previous.isPinned,
            // The whole point of recognising a repeat: the same thing copied again is
            // this clip happening once more, not a new one.
            timesCopied: previous.timesCopied + 1)
    }

    /// Applies one edit to one clip, then the retention rules, then writes.
    private func change(
        _ id: UUID, keeping retention: ClipRetention, _ edit: (inout Clip) -> Void
    ) throws(ClipboardStoreError) -> [Clip] {
        var clips = loaded()
        if let index = clips.firstIndex(where: { $0.id == id }) { edit(&clips[index]) }
        let kept = retained(clips, keeping: retention)
        try save(kept)
        return kept
    }

    /// Two clocks, and only one of them ticks.
    ///
    /// Anything ``Clip/isKept`` survives unconditionally: it is exempt from the window
    /// and it is not counted against the cap. The user aliased it, filed it or pinned
    /// it, which is them saying "this one stays", and losing it would be the worst thing
    /// this app could do — worse than keeping too much, worse than a slow write.
    ///
    /// History gets the window and then the cap. The cap is applied to history alone,
    /// so a hundred pinned clips cannot push the tenth-most-recent copy out.
    ///
    /// The two are recombined by filtering the original list rather than by concatenating
    /// the halves, which keeps arrival order in one pass and without a sort.
    private func retained(_ clips: [Clip], keeping retention: ClipRetention) -> [Clip] {
        // Nothing the user kept is ever a candidate. Not "exempt from the rules below" as
        // a special case checked in three places, but absent from the candidate list
        // entirely — ``ClipClass/kept`` has no tier, so there is no rule for it to be an
        // exception to. Naming, filing or pinning a clip is the user saying they will
        // want it later, and every bound here is about the things they did not say that
        // about.
        let history = clips.filter { ClipClass(of: $0).isEvictable }
        let surviving = history.filter { survives($0, keeping: retention) }

        // The count cap, per pool. Pools rather than one shared cap for the reason the
        // panel's two tabs exist: a morning of dictating must not push out yesterday's
        // ⌘C, and neither may either of them push out a picture. `clips` arrives
        // newest-first, so taking the first N of each pool keeps the newest.
        var taken: [ClipClass: Int] = [:]
        var within: Set<UUID> = []
        for clip in surviving {
            let pool = ClipClass(of: clip)
            guard let tier = budget.tier(for: pool), taken[pool, default: 0] < tier.items
            else { continue }
            taken[pool, default: 0] += 1
            within.insert(clip.id)
        }

        let kept = clips.filter { !ClipClass(of: $0).isEvictable || within.contains($0.id) }
        return withinDisk(withinMemory(kept))
    }

    /// What a clip costs the process to be holding: its words.
    ///
    /// Deliberately not its picture. This used to add `image.bytes`, which is the size of
    /// a file on disk that the process has never read — so the figure was a mixture of two
    /// units and the memory quota it fed was measuring the wrong thing by a factor of a
    /// thousand. The disk is asked about separately, in ``withinDisk(_:)``, where the
    /// number means what it says.
    static func weight(of clip: Clip) -> Int {
        clip.text.utf8.count + (clip.richText?.utf8.count ?? 0)
    }

    static func weight(of clips: [Clip]) -> Int {
        clips.reduce(0) { $0 + weight(of: $1) }
    }

    /// Drops the least recently used clips of a pool until it fits its memory quota.
    ///
    /// Least recently *used*, which is what ``Clip/lastUsedAt`` exists to record. The rule
    /// this replaces was "fewest copies, then oldest", and its known weakness turned out
    /// to be the common case rather than a corner: a value copied twenty times last month
    /// outranked one pasted twice this morning, so the clip somebody had leaned on all
    /// week was the first thing thrown away.
    ///
    /// Only the two text pools are weighed here, because only they are in memory. A
    /// picture's bytes are a file — the process never holds them — so what a picture costs
    /// in RAM is its thumbnail, and that is bounded where the thumbnails actually live.
    /// Weighing image records here would be measuring the disk and calling it memory.
    private func withinMemory(_ clips: [Clip]) -> [Clip] {
        var dropped: Set<UUID> = []
        for pool in [ClipClass.copied, .dictation] {
            guard let tier = budget.tier(for: pool), tier.bytes > 0 else { continue }
            let list = clips.filter { ClipClass(of: $0) == pool }
            var weight = Self.weight(of: list)
            guard weight > tier.bytes else { continue }
            for clip in list.sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) where weight > tier.bytes {
                dropped.insert(clip.id)
                weight -= Self.weight(of: clip)
            }
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// And drops the least recently used pictures until the folder fits its disk budget.
    ///
    /// A separate question from memory and answered separately, because the answer differs
    /// by three orders of magnitude: a thousand screenshots is a gigabyte on disk and
    /// nothing at all in RAM until somebody scrolls past them.
    private func withinDisk(_ clips: [Clip]) -> [Clip] {
        guard budget.disk > 0 else { return clips }
        let pictures = clips.filter { ClipClass(of: $0) == .images }
        var weight = pictures.reduce(0) { $0 + ($1.image?.bytes ?? 0) }
        guard weight > budget.disk else { return clips }
        var dropped: Set<UUID> = []
        for clip in pictures.sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) where weight > budget.disk {
            dropped.insert(clip.id)
            weight -= clip.image?.bytes ?? 0
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// Whether an unkept clip is still inside the window.
    ///
    /// Zero days keeps nothing, which is the honest reading of a setting that says
    /// history is not wanted.
    private func survives(_ clip: Clip, keeping retention: ClipRetention) -> Bool {
        // The pool's own window where it has one, and the user's setting where it does
        // not. Pictures have their own and shorter default: a screenshot is worth keeping
        // for as long as you are working on the thing you screenshotted, and it costs a
        // thousand times what a sentence costs to keep for the same fortnight. Words are
        // the user's to choose the window for, because a dictation is a record of
        // something they said.
        // A dictation's window comes from the user's transcript setting when they have
        // one, because it is the same transcript as the one in the history and they set
        // that window on a screen that did not mention this file.
        let clipClass = ClipClass(of: clip)
        let days =
            clipClass == .dictation
            ? (retention.dictationDays ?? budget.tier(for: clipClass)?.days ?? retention.days)
            : (budget.tier(for: clipClass)?.days ?? retention.days)
        guard days > 0 else { return false }
        return clip.copiedAt.addingTimeInterval(Double(days) * 86_400) > retention.now
    }

    // MARK: - The two files

    /// Where the clips the user saved are kept: beside the history, and never in it.
    ///
    /// Two files rather than one flag inside one file, because "saved" is a promise about
    /// surviving and a shared file is shared fate. Everything that can happen to the
    /// history — a truncated write, a half-finished sync, a hand edit, a build that wrote
    /// a shape this one cannot read — used to happen to the aliases and pins too, and
    /// ``read()`` answers an unreadable file with an empty list, so the loss became
    /// permanent on the next ordinary ⌘C. Measured before this was written: one damaged
    /// byte took a clip aliased `/pgprod` with it and the next copy wrote the emptiness
    /// down.
    ///
    /// Derived from the history's own path rather than injected, so the pair travels
    /// together: move or copy the folder and the clipboard arrives whole.
    ///
    /// This is also the file that outlives this design. When saved clips move to a
    /// database they move as a set, and a set is what this already is.
    var savedFile: URL {
        file.deletingLastPathComponent()
            .appending(path: "saved.v1.json", directoryHint: .notDirectory)
    }

    /// The list, read from disk the first time and from memory thereafter.
    ///
    /// One list to everything above here. The split is a fact about the disk, not about
    /// the clipboard: a caller asking what the user has copied should not have to know
    /// there are two files, and every rule about ordering, retention and eviction reads
    /// the same list it always did.
    private func loaded() -> [Clip] {
        if let wholeList { return wholeList }
        // A clipboard written before the split has its saved clips inside the history
        // file. They are partitioned here and written to their own file by the next
        // ordinary write, which is enough: nothing above this can tell the difference,
        // and a read that writes is a surprise nobody reading this call site would expect.
        let fromSavedFile = read(savedFile)
        persistedSaved = fromSavedFile
        let stored = fromSavedFile + read(file)
        let list = Self.interleaving(
            saved: stored.filter(\.isKept), history: stored.filter { !$0.isKept })
        savedClips = list.filter(\.isKept)
        historyClips = list.filter { !$0.isKept }
        wholeList = list
        sweepOnce(against: list)
        return list
    }

    /// The two lists as one, newest first.
    ///
    /// A two-way merge rather than a sort, and that is not a micro-optimisation: each
    /// list is already in arrival order, and a merge keeps both of those orders intact
    /// where a sort would be free to reorder equal timestamps differently on each call.
    /// The panel counts rows, so two draws of an unchanged clipboard disagreeing about
    /// which one is third is the one thing this cannot do.
    static func interleaving(saved: [Clip], history: [Clip]) -> [Clip] {
        var out: [Clip] = []
        out.reserveCapacity(saved.count + history.count)
        var left = 0
        var right = 0
        while left < saved.count, right < history.count {
            if saved[left].copiedAt >= history[right].copiedAt {
                out.append(saved[left])
                left += 1
            } else {
                out.append(history[right])
                right += 1
            }
        }
        out.append(contentsOf: saved[left...])
        out.append(contentsOf: history[right...])
        return out
    }

    /// One reconciliation per launch, for pictures orphaned before this process started.
    ///
    /// ``save(_:)`` catches a file the moment it stops being referenced, which handles
    /// everything from here on. It cannot handle what is already there: a build that
    /// leaked pictures leaked them permanently, because no future write ever drops a name
    /// that was already absent from the list.
    ///
    /// Skipped when the list is empty, and that is the whole safety of it. ``read()``
    /// answers with nothing for a file that is missing, truncated or written by another
    /// build — so an empty list is not evidence that the user has no pictures, and
    /// sweeping on one would delete every picture they have over a bad read.
    private func sweepOnce(against clips: [Clip]) {
        guard !hasSwept, !clips.isEmpty else { return }
        hasSwept = true
        forgetOrphanedImages()
    }

    /// Reads one file, answering with nothing when there is nothing readable there.
    ///
    /// Absent, unreadable, truncated, hand-edited, or written by a build that knew a
    /// different shape — to a user those all mean the same thing, which is that the
    /// panel should still open. Salvaging clip by clip is not attempted: our own writes
    /// are atomic, so the realistic corruption is a whole file somebody mangled, and
    /// half a clipboard restored is harder to explain than none.
    ///
    /// Answering empty is exactly why the two files are separate. It is the right answer
    /// for a history nobody promised to keep and the wrong one for a clip somebody named,
    /// and one file cannot give two answers.
    private func read(_ url: URL) -> [Clip] {
        guard let data = try? Data(contentsOf: url),
            let clips = try? JSONDecoder().decode([Clip].self, from: data)
        else { return [] }
        return clips
    }

    /// Puts the list in memory and on disk, in that order.
    ///
    /// Memory first, and unconditionally, so that a disk which refuses does not also
    /// cost the user the pin they just set for as long as the app stays open. The error
    /// still reaches them: what they lose is the change surviving a quit, not the change.
    /// The one place every write goes through, which is why the picture sweep lives here.
    ///
    /// The split happens here, and nowhere above it. A clip belongs to whichever file
    /// ``Clip/isKept`` says it does, so naming, filing or pinning a clip *moves* it —
    /// the same write that gives it an alias is the write that takes it out of the
    /// history file — and removing the last of those three moves it back.
    ///
    /// The saved file is only written when what belongs in it has changed. Nearly every
    /// write here is an ordinary ⌘C, and rewriting somebody's permanent collection to
    /// record a copy they will not keep is both wasted work and a needless chance to
    /// corrupt it.
    ///
    /// ``forgetOrphanedImages()`` documented itself as being called after the retention
    /// sweep and was in fact called from nowhere at all, so every picture whose clip was
    /// deleted or aged out stayed on disk for ever. A clipboard that keeps screenshots
    /// and never lets go of one grows without limit; four had already accumulated in a
    /// morning's testing.
    ///
    /// Only when a file stops being referenced, so an ordinary text copy — which is
    /// nearly every write — never pays for a directory scan.
    private func save(_ clips: [Clip]) throws(ClipboardStoreError) {
        let before = Set(loaded().compactMap(\.image?.file))
        let wasSaved = persistedSaved ?? []
        let nowSaved = clips.filter(\.isKept)
        let nowHistory = clips.filter { !$0.isKept }

        savedClips = nowSaved
        historyClips = nowHistory
        wholeList = clips

        // The permanent one first. Should the disk refuse after this, the history is
        // stale by one copy and the collection is not, which is the right way round to
        // fail. And only when it has changed: nearly every write here is an ordinary ⌘C,
        // and rewriting somebody's permanent collection to record a copy they will not
        // keep is both wasted work and a needless chance to corrupt it.
        if nowSaved != wasSaved {
            try persist(nowSaved, to: savedFile)
            persistedSaved = nowSaved
        }
        try persist(nowHistory, to: file)

        if !before.subtracting(Set(clips.compactMap(\.image?.file))).isEmpty {
            forgetOrphanedImages()
        }
    }

    /// Writes a whole list, or removes its file when nothing is left to keep.
    ///
    /// Atomically, so that a crash or a full disk cannot leave behind the truncated file
    /// ``read(_:)`` would then have to throw away. Removing rather than writing an empty
    /// array means an emptied clipboard leaves nothing of the user's on disk at all,
    /// which is what "Clear Clipboard" says on the tin.
    private func persist(_ clips: [Clip], to url: URL) throws(ClipboardStoreError) {
        do {
            guard !clips.isEmpty else {
                try removeFile(url)
                return
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(clips).write(to: url, options: .atomic)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Deletes a file if it is there. Nothing to delete is success, not a failure.
    private func removeFile(_ url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: url)
    }
}
