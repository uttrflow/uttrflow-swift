// Tests for noticing copies, with a fake clipboard.

import Foundation
import Synchronization
import Testing

@testable import UttrflowClipboard

/// A clipboard nobody else can reach, with the change count under the test's control.
final class FakeClipboard: ClipboardSource, Sendable {
    private struct State {
        var count = 0
        var text: String?
        var html: String?
        var picture: (data: Data, width: Int, height: Int)?
        var application: String?
        var reads = 0
        var contentReads = 0
    }

    private let state = Mutex(State())

    /// Writes to the clipboard as another application would: the contents change and the count goes up.
    func write(
        _ text: String?, html: String? = nil,
        picture: (data: Data, width: Int, height: Int)? = nil, from application: String? = nil
    ) {
        state.withLock {
            $0.count += 1
            $0.text = text
            $0.html = html
            $0.picture = picture
            $0.application = application
        }
    }

    var reads: Int { state.withLock(\.reads) }
    var contentReads: Int { state.withLock(\.contentReads) }

    func changeCount() -> Int {
        state.withLock {
            $0.reads += 1
            return $0.count
        }
    }

    func text() -> String? {
        state.withLock {
            $0.contentReads += 1
            return $0.text
        }
    }

    func html() -> String? { state.withLock(\.html) }

    /// K4 — a picture the test put on the clipboard.
    func image() -> (data: Data, width: Int, height: Int)? { state.withLock(\.picture) }

    func frontmostApplicationName() -> String? { state.withLock(\.application) }
}

@Suite("Noticing that something was copied")
struct PasteboardWatcherTests {
    private func watcher(_ clipboard: FakeClipboard, now: Date? = nil) -> PasteboardWatcher {
        let instant = now ?? noon
        return PasteboardWatcher(source: clipboard, now: { instant })
    }

    // MARK: - Noticing

    @Test("notices a copy and works out what it was")
    func noticesACopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("https://example.com", from: "Safari")

        let clip = await watcher.newClip(at: noon)?.clip

        #expect(clip?.text == "https://example.com")
        #expect(clip?.kind == .link)
        #expect(clip?.source == "Safari")
        #expect(clip?.copiedAt == noon)
    }

    /// Whatever is on the clipboard at launch was copied before Uttrflow was watching.
    @Test("adopts whatever was already there rather than claiming it")
    func firstTickTakesABaseline() async {
        let clipboard = FakeClipboard()
        clipboard.write("copied before Uttrflow started")
        let watcher = watcher(clipboard)

        #expect(await watcher.newClip(at: noon)?.clip == nil)
        clipboard.write("copied since")
        #expect(await watcher.newClip(at: noon)?.clip.text == "copied since")
    }

    @Test("says nothing at all while nothing is copied")
    func quietWhenNothingChanges() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("once")
        _ = await watcher.newClip(at: noon)?.clip

        #expect(await watcher.newClip(at: noon)?.clip == nil)
        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    /// A tick is one integer read and nothing else, which makes five ticks a second affordable.
    @Test("reads the contents only once the count has moved")
    func idleTicksAreCheap() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("something")
        _ = await watcher.newClip(at: noon)?.clip
        let after = clipboard.contentReads

        for _ in 1...20 { _ = await watcher.newClip(at: noon)?.clip }

        #expect(clipboard.contentReads == after)
        #expect(clipboard.reads > 20)
    }

    @Test("ignores a clipboard holding something that is not text")
    func nonTextClipboard() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write(nil)

        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    @Test("ignores a copy that is nothing but whitespace")
    func blankCopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("  \n\t ")

        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    /// Whitespace is skipped without losing the place, so the next real copy is still noticed.
    @Test("keeps watching after skipping something blank")
    func blankCopyDoesNotBlind() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("   ")
        _ = await watcher.newClip(at: noon)?.clip

        clipboard.write("real")
        #expect(await watcher.newClip(at: noon)?.clip.text == "real")
    }

    // MARK: - Not noticing ourselves

    /// Uttrflow's own paste writes the clipboard and must not come back as a copy.
    @Test("ignores the write Uttrflow announced")
    func ignoresAnnouncedWrite() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("copied by the user")
        _ = await watcher.newClip(at: noon)?.clip

        watcher.ignoreNextWrite()
        clipboard.write("copied by the user")

        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    /// The announcement comes before the write, because a tick lands between the two often enough.
    @Test("ignores the announced write even when a tick lands in the middle of it")
    func announcementCoversTheWrite() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        watcher.ignoreNextWrite()
        // A tick between the announcement and the write sees nothing and must not spend it.
        #expect(await watcher.newClip(at: noon)?.clip == nil)
        clipboard.write("pasted by Uttrflow")

        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    /// The failure this prevents: a copy in the same tick as a paste never reaching the panel.
    @Test("a copy that lands in the same tick as an Uttrflow paste is still noticed")
    func aCopyRacingThePasteSurvives() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        clipboard.write("pasted by Uttrflow")
        // Copied before the next tick, so one tick sees both changes.
        clipboard.write("copied by the user")

        #expect(await watcher.newClip(at: noon)?.clip.text == "copied by the user")
    }

    @Test("still ignores its own write when the copy arrives first")
    func announcementSurvivesUntilItsOwnWriteArrives() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        clipboard.write("copied by the user")
        #expect(await watcher.newClip(at: noon)?.clip.text == "copied by the user")

        // Not spent by somebody else's copy, so Uttrflow's own write is still ignored.
        clipboard.write("pasted by Uttrflow")
        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    @Test("goes back to noticing copies after the announced write")
    func announcementIsSpentOnce() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        watcher.ignoreNextWrite()
        clipboard.write("pasted by Uttrflow")
        _ = await watcher.newClip(at: noon)?.clip

        clipboard.write("copied by the user")
        #expect(await watcher.newClip(at: noon)?.clip.text == "copied by the user")
    }

    /// An announcement whose write never happened must not sit armed and swallow a later copy.
    @Test("disbelieves an announcement whose write never arrived")
    func staleAnnouncementLapses() async {
        let clipboard = FakeClipboard()
        let clock = Mutex(noon)
        let watcher = PasteboardWatcher(source: clipboard, now: { clock.withLock { $0 } })

        // Announced, and then the write throws before it reaches the clipboard.
        watcher.ignoreNextWrite()

        // Minutes later, long past the announcement's lifetime.
        let later = noon.addingTimeInterval(PasteboardWatcher.announcementLifetime + 60)
        clock.withLock { $0 = later }
        clipboard.write("copied by the user, long afterwards")

        #expect(await watcher.newClip(at: later)?.clip.text == "copied by the user, long afterwards")
    }

    /// An announcement made a moment ago is still believed; the tick can be a poll interval behind.
    @Test("still believes an announcement made a moment ago")
    func freshAnnouncementHolds() async {
        let clipboard = FakeClipboard()
        let clock = Mutex(noon)
        let watcher = PasteboardWatcher(source: clipboard, now: { clock.withLock { $0 } })

        watcher.ignoreNextWrite()
        let soon = noon.addingTimeInterval(PasteboardWatcher.announcementLifetime)
        clock.withLock { $0 = soon }
        clipboard.write("pasted by Uttrflow")

        #expect(await watcher.newClip(at: soon)?.clip == nil)
    }

    // MARK: - Pasting a clip does not disturb the list

    /// Pressing Return on the third row pastes it and leaves the panel untouched.
    @Test("pasting a clip neither duplicates it nor moves it")
    func pastingLeavesTheListAlone() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let window = week()
        let clipboard = FakeClipboard()
        let clock = Mutex(noon)
        let watcher = PasteboardWatcher(source: clipboard, now: { clock.withLock { $0 } })

        /// One turn of the real loop: time moves on by a poll interval, then a tick.
        func tick() async throws {
            clock.withLock { $0 += 0.2 }
            if let clip = await watcher.newClip(at: clock.withLock { $0 })?.clip {
                try await store.record(clip, keeping: window)
            }
        }

        for text in ["one", "two", "three"] {
            clipboard.write(text)
            try await tick()
        }
        #expect(await store.clips(keeping: window).map(\.text) == ["three", "two", "one"])

        // The user picks the third row. Uttrflow announces, writes and presses ⌘V.
        watcher.ignoreNextWrite()
        clipboard.write("one")
        try await tick()

        #expect(await store.clips(keeping: window).map(\.text) == ["three", "two", "one"])
    }

    /// The second line of defence: deduplication refuses a second row even if a paste slips past.
    @Test("still refuses a duplicate row if a paste slips past the announcement")
    func deduplicationBacksUpTheAnnouncement() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let window = week()
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        clipboard.write("one")
        let first = try #require(await watcher.newClip(at: noon)?.clip)
        try await store.record(first, keeping: window)

        // No announcement this time: the write comes back as a copy.
        clipboard.write("one")
        let again = try #require(await watcher.newClip(at: noon)?.clip)
        let clips = try await store.record(again, keeping: window)

        #expect(clips.map(\.text) == ["one"])
    }

    // MARK: - The loop

    @Test("keeps watching on its own until it is cancelled")
    func theLoop() async throws {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(
            source: clipboard, interval: .milliseconds(1), now: { noon })
        let (clips, continuation) = AsyncStream.makeStream(of: NoticedClip.self)

        let task = Task { await watcher.run { continuation.yield($0) } }
        var received = clips.makeAsyncIterator()

        clipboard.write("first")
        #expect(await received.next()?.clip.text == "first")
        clipboard.write("second")
        #expect(await received.next()?.clip.text == "second")

        task.cancel()
        await task.value
    }

    /// Two hundred milliseconds, because the gap between ⌘C and ⇧⌘V is a hand movement.
    @Test("polls often enough to keep up with the gesture")
    func interval() {
        #expect(PasteboardWatcher.pollInterval == .milliseconds(200))
    }

    /// Left to itself it reads the real clock, which is what the app gets.
    @Test("times its own announcements by the wall clock when it is not told otherwise")
    func defaultClock() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(source: clipboard)

        watcher.ignoreNextWrite()
        clipboard.write("pasted by Uttrflow")
        #expect(await watcher.newClip(at: Date()) == nil)

        clipboard.write("copied by the user")
        #expect(await watcher.newClip(at: Date())?.clip.text == "copied by the user")
    }
}
