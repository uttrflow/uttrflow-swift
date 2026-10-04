// Polls the clipboard and reports new copies, ignoring Uttrflow's own announced writes.

public import struct Foundation.Data
public import struct Foundation.Date
public import struct Foundation.UUID

private import Synchronization
private import Dispatch
private import os

/// Notices when the user copies something, by polling, which is the only mechanism macOS offers.
public actor PasteboardWatcher {
    private struct ApplicationSample: Equatable {
        let name: String?
        let bundleIdentifier: String?

        init(source: any ClipboardSource) {
            let application = source.frontmostApplication()
            name = application.name
            bundleIdentifier = application.bundleIdentifier
        }
    }

    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "clipboard")

    /// Where a clipboard read runs, so a writer that never answers holds no thread the app needs.
    private static let readQueue = DispatchQueue(
        label: "com.uttrflow.clipboard-read", qos: .userInitiated, attributes: .concurrent)

    /// How often the change count is read; the panel catches up as it opens, so this is set by battery. See `Docs/performance-idle.md`.
    public static let pollInterval = Duration.milliseconds(500)

    /// How far the system may move one poll to coalesce it with other wakeups: a fifth of the interval.
    static func tolerance(for interval: Duration) -> Duration {
        interval / 5
    }

    /// Bounds announcements from a burst of app-owned writes between clipboard polls.
    static let maxPendingAnnouncements = 32

    private nonisolated let source: any ClipboardSource
    private let interval: Duration
    /// The same bound the store applies, asked here so an oversize copy is never classified.
    private let budget: ClipboardBudget
    private nonisolated let now: @Sendable () -> Date

    /// Uttrflow's own writes, behind a `Mutex` because a write cannot `await` to announce itself.
    private nonisolated let announced = Mutex<[Announcement]>([])

    /// A picture as the clipboard hands it over.
    typealias ClipboardPicture = (data: Data, width: Int, height: Int)

    /// The last change count dealt with, read at construction so neither launch case is wrong.
    private var seen: Int
    /// Bundle identifiers excluded from capture; ambiguous provenance is excluded as well.
    private var excludedApplications: Set<String> = []
    /// The last application's identity sampled at a clipboard polling tick.
    private var lastApplication: ApplicationSample
    /// A focus change during a slow clipboard read makes its pending copy's provenance unknown.
    private var applicationChangedWhileReading = false

    /// How long a promised or Universal Clipboard read may take before the copy is given up on.
    public static let defaultReadLimit = Duration.seconds(2)

    /// This watcher's limit on one clipboard read, which a test shortens.
    private let readLimit: Duration

    /// Set while a read is outstanding, so a blocked one cannot be started again by the next tick.
    private var isReading = false

    /// How many reads may be waiting on `readQueue` at once, past which a tick skips rather than starting another.
    static let maxOutstandingReads = 4

    /// Reads dispatched to `readQueue` that have not yet returned, whether or not their caller is still waiting.
    private(set) var outstandingReads = 0

    public init(
        source: any ClipboardSource,
        interval: Duration = PasteboardWatcher.pollInterval,
        budget: ClipboardBudget = .standard,
        readLimit: Duration = PasteboardWatcher.defaultReadLimit,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = source
        self.interval = interval
        self.budget = budget
        self.readLimit = readLimit
        self.now = now
        self.seen = source.changeCount()
        self.lastApplication = ApplicationSample(source: source)
    }

    // MARK: - Ignoring ourselves

    /// Announces a write — call immediately before it — naming its text. See `Docs/insertion.md`.
    @discardableResult
    public nonisolated func ignoreNextWrite(of text: String) -> @Sendable (Int?) -> Void {
        announce(.text(text))
    }

    /// K4 — announces a picture write, named by the bytes it puts there. See `Docs/insertion.md`.
    @discardableResult
    public nonisolated func ignoreNextPicture(_ data: Data) -> @Sendable (Int?) -> Void {
        announce(.picture(data))
    }

    /// Reserves an announcement before the write, then records its exact resulting generation.
    private nonisolated func announce(_ written: Written) -> @Sendable (Int?) -> Void {
        let before = source.changeCount()
        let id = UUID()
        announced.withLock { pending in
            if pending.count == Self.maxPendingAnnouncements { pending.removeFirst() }
            pending.append(Announcement(id: id, after: before, changeCount: nil, wrote: written))
        }
        return { [self] changeCount in
            guard let changeCount else { return withdrawAnnouncement(id) }
            announced.withLock { pending in
                guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
                pending[index].changeCount = changeCount
            }
        }
    }

    /// Withdraws a write that the pasteboard refused or that could not be read back.
    private nonisolated func withdrawAnnouncement(_ id: UUID) {
        announced.withLock { pending in pending.removeAll { $0.id == id } }
    }

    /// Drops announcements that could have described a change whose contents stayed unreadable.
    private nonisolated func withdrawAnnouncements(forChange count: Int) {
        announced.withLock { pending in
            pending.removeAll { $0.changeCount.map { count >= $0 } ?? (count > $0.after) }
        }
    }

    /// Whether this change is the announced write, matched on what it put there. See `Docs/insertion.md`.
    private nonisolated func claims(_ count: Int, holding text: String?, picture: Data?) -> Bool {
        announced.withLock { pending in
            // Once a later generation is observed, an earlier write cannot describe it.
            pending.removeAll { $0.changeCount.map { count > $0 } ?? false }
            guard
                let match = pending.firstIndex(where: { announcement in
                    if let writtenCount = announcement.changeCount {
                        guard count == writtenCount else { return false }
                    } else {
                        // The write may be visible a moment before its synchronous result is reported.
                        guard count > announcement.after else { return false }
                    }
                    switch announcement.wrote {
                    case .text(let wrote): return text == wrote
                    case .picture(let wrote): return text == nil && picture == wrote
                    }
                })
            else { return false }
            pending.remove(at: match)
            return true
        }
    }

    // MARK: - One tick

    /// Reads the clipboard once, answering a clip only when the user has copied something new.
    public func newClip(at date: Date) async -> NoticedClip? {
        let application = ApplicationSample(source: source)
        let applicationChanged = application != lastApplication
        lastApplication = application
        // A read another process has to answer is still running; a second one would only queue behind it.
        guard !isReading else {
            applicationChangedWhileReading = applicationChangedWhileReading || applicationChanged
            return nil
        }
        let count = source.changeCount()
        guard count != seen else {
            applicationChangedWhileReading = false
            return nil
        }
        seen = count
        let provenanceIsUnknown = applicationChanged || applicationChangedWhileReading
        applicationChangedWhileReading = false
        if provenanceIsUnknown, !excludedApplications.isEmpty { return nil }
        if !provenanceIsUnknown, let identifier = application.bundleIdentifier,
            excludedApplications.contains(identifier.lowercased())
        {
            return nil
        }

        isReading = true
        defer { isReading = false }
        // Fetched only now, and once, so an idle tick costs one integer read.
        guard let copied = await bounded({ [source] in source.text() }) else {
            withdrawAnnouncements(forChange: count)
            return nil
        }
        let rtf: Data?
        if copied == nil {
            guard let data = await bounded({ [source] in source.rtf() }) else {
                withdrawAnnouncements(forChange: count)
                return nil
            }
            rtf = data.flatMap {
                budget.largestClip == 0 || $0.count <= budget.largestClip ? $0 : nil
            }
        } else {
            rtf = nil
        }
        let rtfText = rtf.flatMap(RichTextPlainForm.plainText(fromRTF:))
        // Read once, bounded and outside the lock, and only when a picture announcement could claim it.
        var read: ClipboardPicture?? = .none
        let hasPicture = source.hasPicture()
        if copied == nil, hasPicture, awaitsPicture(at: count) {
            guard let picture = await bounded({ [source] in source.image() }) else {
                withdrawAnnouncements(forChange: count)
                return nil
            }
            read = .some(picture)
        }
        guard !claims(count, holding: copied, picture: read??.data) else { return nil }

        // A copy its writer marked as not for history is never recorded, text or picture.
        guard let markers = await bounded({ [source] in source.markers() }) else { return nil }
        guard markers.allowsRecording else { return nil }
        // A write between the reads pairs one copy with another's markers; the next tick reads it whole.
        guard source.changeCount() == count else { return nil }

        // K4 — a picture, asked first because the branch below returns for anything textless.
        let picture: ClipboardPicture?
        if let read {
            picture = read
        } else if hasPicture {
            picture = await bounded({ [source] in source.image() }) ?? nil
        } else {
            picture = nil
        }
        if copied == nil, !ClipContent.isWorthKeeping(rtfText ?? ""), let picture {
            guard !markers.contains(.concealed), source.changeCount() == count else { return nil }
            return NoticedClip(
                clip: Clip(
                    text: "", kind: .image, copiedAt: date,
                    source: provenanceIsUnknown ? nil : application.name),
                picture: picture)
        }

        // Plain text already over the bound is refused before its rich form is copied out.
        guard fitsTheBound(copied ?? "", nil) else { return nil }
        guard let html = await bounded({ [source] in source.html() }) else { return nil }
        // Again after the last read, so a copy landing during the picture or HTML read is never paired with this one's markers.
        guard source.changeCount() == count else { return nil }
        // Before the conversion, which costs in proportion to the HTML however the bound would judge it.
        guard fitsTheBound(copied ?? "", html) else { return nil }
        // E1 — the plain form is derived only here, where the alternative is no clip at all.
        guard
            let text = copied ?? rtfText ?? html.map(RichTextPlainForm.plainText(fromHTML:)),
            ClipContent.isWorthKeeping(text)
        else { return nil }

        // Before the classifier, which reads the whole string: the store would refuse this anyway.
        guard fitsTheBound(text, html) else { return nil }

        // A concealed copy is a password to its writer, whatever its shape. See Docs/clipboard-secrets.md.
        let classified =
            markers.contains(.concealed)
            ? ClipClassification(kind: .secret, language: nil) : ClipKindDetector.classification(of: text)
        return NoticedClip(
            clip: Clip(
                text: text, kind: classified.kind, copiedAt: date,
                source: provenanceIsUnknown ? nil : application.name,
                // Only of a clip already judged to be code, so prose never pays for the detector.
                language: classified.language,
                // E — kept beside the plain form, never instead of it.
                richText: html),
            picture: picture)
    }

    /// Whether a picture announcement is armed, asked without reading the clipboard.
    private nonisolated func awaitsPicture(at count: Int) -> Bool {
        announced.withLock { pending in
            pending.contains { announcement in
                if let writtenCount = announcement.changeCount, writtenCount != count { return false }
                if case .picture = announcement.wrote { return true }
                return false
            }
        }
    }

    /// One clipboard read, given up on once ``readLimit`` has passed, since the writing app answers it.
    private func bounded<Value: Sendable>(_ read: @escaping @Sendable () -> Value) async -> Value? {
        // A writer that never answers must not be allowed to accumulate one blocked worker per copy.
        guard outstandingReads < Self.maxOutstandingReads else {
            Self.log.notice("too many clipboard reads are already outstanding; this copy is skipped")
            return nil
        }
        outstandingReads += 1
        let race = Mutex<ClipboardRead<Value>>(.waiting)
        // Whichever arrives first answers; the loser finds the answer already given.
        let settle: @Sendable (Value?) -> Void = { value in
            race.withLock { state in
                if case .listening(let continuation) = state { continuation.resume(returning: value) }
                guard case .answered = state else { return state = .answered(value) }
            }
        }
        // On its own thread, never the cooperative pool: a promised read blocks until the writer answers.
        Self.readQueue.async { [weak self] in
            let value = read()
            settle(value)
            // Freed only once the worker itself returns, however late that is against the caller's limit.
            Task { await self?.releaseOutstandingRead() }
        }
        // The limit is a dispatch timer for the same reason: a busy pool must not delay giving up.
        Self.readQueue.asyncAfter(deadline: .now() + readLimit.inSeconds) { settle(nil) }
        let value = await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
            race.withLock { state in
                if case .answered(let value) = state { return continuation.resume(returning: value) }
                state = .listening(continuation)
            }
        }
        if value == nil { Self.log.notice("a clipboard read passed its limit; this copy is skipped") }
        return value
    }

    /// Frees the slot a worker held once it returns, letting a later tick start a new read.
    private func releaseOutstandingRead() {
        outstandingReads -= 1
    }

    /// Whether a clip is small enough to keep, counting both flavours as `ClipboardStore.weight(of:)` does.
    private func fitsTheBound(_ text: String, _ html: String?) -> Bool {
        guard budget.largestClip > 0 else { return true }
        return text.utf8.count + (html?.utf8.count ?? 0) <= budget.largestClip
    }

    /// The clipboard's change count now, read without waiting on the watcher.
    public nonisolated var changeCount: Int { source.changeCount() }

    /// Treats every change up to `count` as seen and forgets any announced write, so nothing from while recording was off is kept.
    public func passOver(upTo count: Int) {
        seen = count
        announced.withLock { $0.removeAll() }
    }

    /// Replaces the local exclusion list without restarting the polling task.
    public func setExcludedApplications(_ bundleIdentifiers: Set<String>) {
        excludedApplications = Set(bundleIdentifiers.map { $0.lowercased() })
    }

    // MARK: - The loop

    /// Watches until cancelled, handing each new clip to `handle` in order.
    public func run(handing handle: @Sendable (NoticedClip) async -> Void) async {
        while true {
            do {
                try await Task.sleep(for: interval, tolerance: Self.tolerance(for: interval))
            } catch { break }
            await catchUp(handing: handle)
        }
    }

    /// Reads the clipboard now rather than at the next poll, so a panel opening shows a copy made a moment before.
    public func catchUp(handing handle: @Sendable (NoticedClip) async -> Void) async {
        if let clip = await newClip(at: now()) { await handle(clip) }
    }
}

/// What an announced write puts on the clipboard, so the change it makes is named rather than guessed.
private enum Written: Sendable, Equatable {
    case text(String)
    case picture(Data)
}

/// An Uttrflow write that has been announced and not yet seen on the clipboard.
private struct Announcement: Sendable {
    let id: UUID
    let after: Int
    var changeCount: Int?
    /// What is about to be written, which the change is matched against.
    let wrote: Written
}

/// A clip the watcher noticed, carrying the picture's bytes until the store can write them.
public struct NoticedClip: Sendable, Equatable {
    public let clip: Clip
    /// K4 — PNG bytes and the size in pixels, for an image copy.
    public let picture: (data: Data, width: Int, height: Int)?

    public init(clip: Clip, picture: (data: Data, width: Int, height: Int)? = nil) {
        self.clip = clip
        self.picture = picture
    }

    public static func == (lhs: NoticedClip, rhs: NoticedClip) -> Bool {
        lhs.clip == rhs.clip && lhs.picture?.data == rhs.picture?.data
            && lhs.picture?.width == rhs.picture?.width
            && lhs.picture?.height == rhs.picture?.height
    }
}

/// Where one bounded clipboard read has got to: nobody waiting yet, somebody waiting, or answered.
private enum ClipboardRead<Value: Sendable>: Sendable {
    case waiting
    case listening(CheckedContinuation<Value?, Never>)
    case answered(Value?)
}
