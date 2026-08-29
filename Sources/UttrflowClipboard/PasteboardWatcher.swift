public import struct Foundation.Data
public import struct Foundation.Date

private import Synchronization

/// Notices when the user copies something.
///
/// macOS offers no notification for this. `NSPasteboard` has a `changeCount` that goes
/// up whenever anything writes to the clipboard and nothing at all that will tell you
/// when it moved, so polling is not a shortcut here — it is the only mechanism there is.
/// Every clipboard manager on the platform does this.
///
/// The loop is separated from the decision on purpose. ``newClip(at:)`` is one tick and
/// takes no time, so every rule below is testable without waiting for anything; ``run``
/// is four lines of scheduling on top of it.
public actor PasteboardWatcher {
    /// How often the change count is read.
    ///
    /// Two hundred milliseconds, and the number is set by the gesture rather than by the
    /// cost. The product is ⌘C somewhere, then ⇧⌘V somewhere else: the fastest anyone
    /// gets from one to the other is a few hundred milliseconds of hand movement, and
    /// the one unforgivable bug in a clipboard manager is opening the panel and not
    /// finding the thing you just copied at the top. Five reads a second sits under that
    /// gap with room to spare. A second would not, and would show a stale list to anyone
    /// who moves quickly.
    ///
    /// The cost of being wrong in the other direction is small enough to spend. A tick
    /// reads one integer over the connection to `pasteboardd` that the process already
    /// holds — no allocation, no copy of the clipboard's contents, which are fetched
    /// only when the count has actually moved. Five of those a second is not measurable
    /// next to what the app does when it is genuinely working, and it runs on the
    /// cooperative pool rather than the main thread, so a slow read cannot touch the
    /// interface.
    public static let pollInterval = Duration.milliseconds(200)

    /// How long an announced write stays announced before it is disbelieved.
    ///
    /// The write follows ``ignoreNextWrite()`` within microseconds, and the tick that
    /// sees it follows within ``pollInterval``. Two seconds is ten times that slack, and
    /// still far shorter than the gap before a person copies something else — so an
    /// announcement whose write never happened, because the paste threw before it
    /// reached the clipboard, cannot sit armed and swallow an unrelated copy later on.
    static let announcementLifetime: Double = 2

    private nonisolated let source: any ClipboardSource
    private let interval: Duration
    private nonisolated let now: @Sendable () -> Date

    /// Uttrflow's own write, announced and not yet accounted for.
    ///
    /// Behind a `Mutex` rather than in the actor's own state, and that is the whole
    /// point of it. The announcement has to be made by whatever performs the write, from
    /// inside a synchronous `setText`, with no opportunity to `await` — anything that
    /// suspended between the write and the announcement would leave a window in which a
    /// tick could fire and record Uttrflow's own paste as a fresh copy.
    private nonisolated let announced = Mutex<(after: Int, at: Date)?>(nil)

    /// The last change count that has been dealt with.
    ///
    /// Read at construction rather than on the first tick, and both halves of that
    /// matter. Reading it at all is what stops whatever was on the clipboard at launch
    /// being claimed as a fresh copy — it was copied before Uttrflow was watching, and a
    /// row at the top of the panel that the user did not just create is at its most
    /// baffling at login, where it would be whatever they were doing yesterday. Reading
    /// it *here* rather than at the first tick is what stops the opposite: a copy made
    /// in the first ``pollInterval`` after launch would otherwise become the baseline
    /// and be lost.
    private var seen: Int

    public init(
        source: any ClipboardSource,
        interval: Duration = PasteboardWatcher.pollInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = source
        self.interval = interval
        self.now = now
        self.seen = source.changeCount()
    }

    // MARK: - Ignoring ourselves

    /// Announces that Uttrflow is about to write to the clipboard, so the change that
    /// follows is not mistaken for the user copying something.
    ///
    /// Uttrflow writes to the clipboard whenever it pastes a clip: `UttrflowInput`'s paste
    /// engine puts the text there, presses ⌘V, and deliberately does not put back what
    /// was there before, because it cannot learn whether the keystroke landed and a
    /// restore that guesses wrong destroys the user's words. So the clipboard is left
    /// holding a clip this watcher has already seen, and the change count has moved.
    /// Left alone, that is a copy — and picking the third row would move it to the top,
    /// reordering the panel under the user's hand every time they used it.
    ///
    /// **Call this immediately before the write, not after.** Before is what makes it
    /// exact: the announcement is in place while the write happens, so a tick landing in
    /// the microseconds between the two still sees an announced change. Announcing
    /// afterwards would leave that window open, and at five ticks a second it would be
    /// hit often enough to be reported as a bug.
    ///
    /// It is deliberately synchronous and deliberately not actor-isolated, so that it
    /// can be called from inside a plain `Pasteboard.setText` — a write is not a caller,
    /// and making this an `await` would put the suppression back in the hands of whoever
    /// remembered to bracket the call.
    ///
    /// The announcement is spent by the first change that follows it, and lapses after
    /// ``announcementLifetime`` if no change ever does.
    public nonisolated func ignoreNextWrite() {
        let before = source.changeCount()
        let at = now()
        announced.withLock { $0 = (after: before, at: at) }
    }

    /// Whether the change now on the clipboard was the one that was announced.
    ///
    /// Takes the announcement whatever the answer, because an announcement that does not
    /// match this change will not match a later one either: counts only ever rise, so a
    /// stale announcement can only swallow something innocent.
    private nonisolated func claims(_ count: Int, at date: Date) -> Bool {
        let pending = announced.withLock { held in
            defer { held = nil }
            return held
        }
        guard let pending else { return false }
        return count > pending.after
            && date.timeIntervalSince(pending.at) <= Self.announcementLifetime
    }

    // MARK: - One tick

    /// Reads the clipboard once, and answers with a clip when the user has copied
    /// something new.
    ///
    /// - Parameter date: When the copy happened, as far as the clip is concerned.
    /// - Returns: The new clip, or `nil` when nothing changed, when the change was
    ///   Uttrflow's own, when the clipboard holds something that is not text, or when
    ///   what it holds is only whitespace.
    public func newClip(at date: Date) -> NoticedClip? {
        let count = source.changeCount()
        guard count != seen else { return nil }
        seen = count

        guard !claims(count, at: date) else { return nil }

        // The contents are fetched only now, once the count says there is a point. This
        // is what keeps a tick to a single integer read for the many seconds at a time
        // when nobody is copying anything.
        // K4 — a picture, when there is no text to prefer. Asked first because the branch
        // below returns for anything textless, and an image copy has no text at all: a
        // screenshot used to leave the tick empty-handed and never became a clip.
        if source.text() == nil, let picture = source.image() {
            return NoticedClip(
                clip: Clip(
                    text: "", kind: .image, copiedAt: date,
                    source: source.frontmostApplicationName()),
                picture: picture)
        }

        let html = source.html()
        // E1 — a copy that offers only a rich flavour still becomes a clip.
        //
        // Some applications put HTML on the pasteboard and no plain string at all. Those
        // copies used to vanish: the guard below found nothing and the tick returned. The
        // plain form is *derived* only here, where the alternative is no clip whatsoever —
        // everywhere else it is the captured one, because a conversion is the thing that
        // can fail and no paste should have to wait on one.
        guard let text = source.text() ?? html.map(RichTextPlainForm.plainText(fromHTML:)),
            ClipContent.isWorthKeeping(text)
        else { return nil }

        let kind = ClipKindDetector.kind(of: text)
        return NoticedClip(
            clip: Clip(
                text: text, kind: kind, copiedAt: date,
                source: source.frontmostApplicationName(),
                // Asked only of a clip already judged to be code. Running the detector over
                // every clip would spend the tick on prose that can never carry a chip.
                language: kind == .code ? CodeLanguage.detect(text) : nil,
                // E — kept beside the plain form, never instead of it.
                richText: html))
    }

    // MARK: - The loop

    /// Watches until the surrounding task is cancelled, handing over each new clip.
    ///
    /// Cancellation is the only way out, and the sleep is where it is noticed:
    /// `Task.sleep` throws immediately on a task that is already cancelled, so it serves
    /// as both the wait and the check. A separate `while !Task.isCancelled` would read
    /// as a second guard and would in fact be unreachable — every path back to the top
    /// of the loop goes through the sleep.
    ///
    /// - Parameter handle: Given each new clip, in order. Recording it is the caller's
    ///   job — the watcher deliberately does not know the store exists, so that noticing
    ///   a copy and keeping one can be tested and changed apart.
    public func run(handing handle: @Sendable (NoticedClip) async -> Void) async {
        while true {
            do { try await Task.sleep(for: interval) } catch { break }
            if let clip = newClip(at: now()) { await handle(clip) }
        }
    }
}

/// A clip the watcher noticed, and the picture that goes with it when there is one.
///
/// The bytes are here rather than on ``Clip`` because a clip is a record and this is a
/// file waiting to be written. Only the store knows the folder, so only the store can
/// finish an image clip — and it must write the file before recording the clip, or the
/// clip would refer to something that is not there.
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
