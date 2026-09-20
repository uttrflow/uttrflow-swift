// Polls the clipboard and reports new copies, ignoring Uttrflow's own announced writes.

public import struct Foundation.Data
public import struct Foundation.Date

private import Synchronization

/// Notices when the user copies something, by polling, which is the only mechanism macOS offers.
public actor PasteboardWatcher {
    /// How often the change count is read; the panel catches up as it opens, so this is set by battery. See `Docs/performance.md`.
    public static let pollInterval = Duration.milliseconds(500)

    /// How far the system may move one poll to coalesce it with other wakeups: a fifth of the interval.
    static func tolerance(for interval: Duration) -> Duration {
        interval / 5
    }

    /// How long an announcement stays armed, so a write that never happened cannot sit waiting.
    static let announcementLifetime: Double = 2

    private nonisolated let source: any ClipboardSource
    private let interval: Duration
    /// The same bound the store applies, asked here so an oversize copy is never classified.
    private let budget: ClipboardBudget
    private nonisolated let now: @Sendable () -> Date

    /// Uttrflow's own write, behind a `Mutex` because a write cannot `await` to announce itself.
    private nonisolated let announced = Mutex<Announcement?>(nil)

    /// The last change count dealt with, read at construction so neither launch case is wrong.
    private var seen: Int

    public init(
        source: any ClipboardSource,
        interval: Duration = PasteboardWatcher.pollInterval,
        budget: ClipboardBudget = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = source
        self.interval = interval
        self.budget = budget
        self.now = now
        self.seen = source.changeCount()
    }

    // MARK: - Ignoring ourselves

    /// Announces a write — call immediately before it — naming its text. See `Docs/insertion.md`.
    public nonisolated func ignoreNextWrite(of text: String) {
        announce(.text(text))
    }

    /// K4 — announces a picture write, named by the bytes it puts there. See `Docs/insertion.md`.
    public nonisolated func ignoreNextPicture(_ data: Data) {
        announce(.picture(data))
    }

    /// Records what is about to be written, reading the count before the write moves it.
    private nonisolated func announce(_ written: Written) {
        let before = source.changeCount()
        let at = now()
        announced.withLock { $0 = Announcement(after: before, at: at, wrote: written) }
    }

    /// Whether this change is the announced write, matched on what it put there. See `Docs/insertion.md`.
    private nonisolated func claims(
        _ count: Int, at date: Date, holding text: String?, picture: () -> Data?
    ) -> Bool {
        announced.withLock { held -> Bool in
            guard let pending = held else { return false }
            // A write that never happened must not sit armed over somebody's copy.
            guard date.timeIntervalSince(pending.at) <= Self.announcementLifetime else {
                held = nil
                return false
            }
            guard count > pending.after else { return false }
            switch pending.wrote {
            case .text(let wrote):
                guard text == wrote else { return false }
            // Read only here, so a tick that has no picture announcement pending never asks for bytes.
            case .picture(let wrote):
                guard text == nil, picture() == wrote else { return false }
            }
            held = nil
            return true
        }
    }

    // MARK: - One tick

    /// Reads the clipboard once, answering a clip only when the user has copied something new.
    public func newClip(at date: Date) -> NoticedClip? {
        let count = source.changeCount()
        guard count != seen else { return nil }
        seen = count

        // Fetched only now, and once, so an idle tick costs one integer read.
        let copied = source.text()
        guard !claims(count, at: date, holding: copied, picture: { source.image()?.data }) else {
            return nil
        }

        // A copy its writer marked as not for history is never recorded, text or picture.
        let markers = source.markers()
        guard markers.allowsRecording else { return nil }
        // A write between the reads pairs one copy with another's markers; the next tick reads it whole.
        guard source.changeCount() == count else { return nil }

        // K4 — a picture, asked first because the branch below returns for anything textless.
        if copied == nil, let picture = source.image() {
            return NoticedClip(
                clip: Clip(
                    text: "", kind: .image, copiedAt: date,
                    source: source.frontmostApplicationName()),
                picture: picture)
        }

        let html = source.html()
        // E1 — the plain form is derived only here, where the alternative is no clip at all.
        guard let text = copied ?? html.map(RichTextPlainForm.plainText(fromHTML:)),
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
                source: source.frontmostApplicationName(),
                // Only of a clip already judged to be code, so prose never pays for the detector.
                language: classified.language,
                // E — kept beside the plain form, never instead of it.
                richText: html))
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
        announced.withLock { $0 = nil }
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
        if let clip = newClip(at: now()) { await handle(clip) }
    }
}

/// What an announced write puts on the clipboard, so the change it makes is named rather than guessed.
private enum Written: Sendable, Equatable {
    case text(String)
    case picture(Data)
}

/// An Uttrflow write that has been announced and not yet seen on the clipboard.
private struct Announcement: Sendable {
    let after: Int
    let at: Date
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
