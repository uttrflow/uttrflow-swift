// Polls the clipboard and reports new copies, ignoring Uttrflow's own announced writes.

public import struct Foundation.Data
public import struct Foundation.Date

private import Synchronization

/// Notices when the user copies something, by polling, which is the only mechanism macOS offers.
public actor PasteboardWatcher {
    /// How often the change count is read, set by how fast a hand moves from ⌘C to ⇧⌘V.
    public static let pollInterval = Duration.milliseconds(200)

    /// How long an announcement stays armed, so a write that never happened cannot sit waiting.
    static let announcementLifetime: Double = 2

    private nonisolated let source: any ClipboardSource
    private let interval: Duration
    private nonisolated let now: @Sendable () -> Date

    /// Uttrflow's own write, behind a `Mutex` because a write cannot `await` to announce itself.
    private nonisolated let announced = Mutex<Announcement?>(nil)

    /// The last change count dealt with, read at construction so neither launch case is wrong.
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

    /// Announces a write — call immediately before it — naming its text. See `Docs/insertion.md`.
    public nonisolated func ignoreNextWrite(of text: String? = nil) {
        let before = source.changeCount()
        let at = now()
        announced.withLock { $0 = Announcement(after: before, at: at, text: text) }
    }

    /// Whether this change is the announced write, matched on its text. See `Docs/insertion.md`.
    private nonisolated func claims(_ count: Int, at date: Date, holding text: String?) -> Bool {
        announced.withLock { held -> Bool in
            guard let pending = held else { return false }
            // A write that never happened must not sit armed over somebody's copy.
            guard date.timeIntervalSince(pending.at) <= Self.announcementLifetime else {
                held = nil
                return false
            }
            guard count > pending.after else { return false }
            // A write with no text to name — a picture — has only the count to go on.
            guard let wrote = pending.text else {
                held = nil
                return true
            }
            guard text == wrote else { return false }
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
        guard !claims(count, at: date, holding: copied) else { return nil }

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

        let kind = ClipKindDetector.kind(of: text)
        return NoticedClip(
            clip: Clip(
                text: text, kind: kind, copiedAt: date,
                source: source.frontmostApplicationName(),
                // Only of a clip already judged to be code, so prose never pays for the detector.
                language: kind == .code ? CodeLanguage.detect(text) : nil,
                // E — kept beside the plain form, never instead of it.
                richText: html))
    }

    // MARK: - The loop

    /// Watches until cancelled, handing each new clip to `handle` in order.
    public func run(handing handle: @Sendable (NoticedClip) async -> Void) async {
        while true {
            do { try await Task.sleep(for: interval) } catch { break }
            if let clip = newClip(at: now()) { await handle(clip) }
        }
    }
}

/// An Uttrflow write that has been announced and not yet seen on the clipboard.
private struct Announcement: Sendable {
    let after: Int
    let at: Date
    /// What is about to be written, or `nil` for a write carrying no text.
    let text: String?
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
