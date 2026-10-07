// Tests for noticing copies, with a fake clipboard.

import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowClipboard

/// A clipboard nobody else can reach, with the change count under the test's control.
final class FakeClipboard: ClipboardSource, Sendable {
    private struct State {
        var count = 0
        var text: String?
        var rtf: Data?
        var html: String?
        var picture: (data: Data, width: Int, height: Int)?
        var application: String?
        var bundleIdentifier: String?
        var markers: PasteboardMarkers = []
        var landsDuringMarkers: (text: String, markers: PasteboardMarkers)?
        var reads = 0
        var contentReads = 0
        var htmlReads = 0
    }

    private let state = Mutex(State())

    /// Writes to the clipboard as another application would: the contents change and the count goes up.
    @discardableResult
    func write(
        _ text: String?, html: String? = nil, rtf: Data? = nil,
        picture: (data: Data, width: Int, height: Int)? = nil, from application: String? = nil,
        marked markers: PasteboardMarkers = [], bundleIdentifier: String? = nil
    ) -> Int {
        state.withLock {
            $0.count += 1
            $0.text = text
            $0.rtf = rtf
            $0.html = html
            $0.picture = picture
            $0.application = application
            $0.bundleIdentifier = bundleIdentifier
            $0.markers = markers
            return $0.count
        }
    }

    /// Changes focus without changing clipboard contents or their writer.
    func focus(on application: String?, bundleIdentifier: String? = nil) {
        state.withLock {
            $0.application = application
            $0.bundleIdentifier = bundleIdentifier
        }
    }

    var reads: Int { state.withLock(\.reads) }
    var contentReads: Int { state.withLock(\.contentReads) }
    var htmlReads: Int { state.withLock(\.htmlReads) }

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

    func html() -> String? {
        state.withLock {
            $0.htmlReads += 1
            return $0.html
        }
    }

    func rtf() -> Data? { state.withLock(\.rtf) }

    /// Arms a write that lands while the watcher is reading the markers of the copy before it.
    func writeWhileMarkersAreRead(_ text: String, marked markers: PasteboardMarkers = []) {
        state.withLock { $0.landsDuringMarkers = (text, markers) }
    }

    func markers() -> PasteboardMarkers {
        state.withLock {
            if let landing = $0.landsDuringMarkers {
                $0.landsDuringMarkers = nil
                $0.count += 1
                $0.text = landing.text
                $0.markers = landing.markers
            }
            return $0.markers
        }
    }

    /// K4 — a picture the test put on the clipboard.
    func image() -> (data: Data, width: Int, height: Int)? { state.withLock(\.picture) }
    func hasPicture() -> Bool { state.withLock { $0.picture != nil } }

    func frontmostApplicationName() -> String? { state.withLock(\.application) }
    func frontmostApplicationBundleIdentifier() -> String? { state.withLock(\.bundleIdentifier) }
    func frontmostApplication() -> (name: String?, bundleIdentifier: String?) {
        state.withLock { ($0.application, $0.bundleIdentifier) }
    }
}

@Suite("Noticing that something was copied")
struct PasteboardWatcherTests {
    @Test("ignores a BOM-prefixed write when the pasteboard omits the leading mark")
    func ignoresPasteboardReadbackWithoutLeadingByteOrderMark() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let finishWrite = watcher.ignoreNextWrite(of: "\u{FEFF}hello")

        finishWrite(clipboard.write("hello"))

        #expect(await watcher.newClip(at: noon) == nil)
    }

    private func watcher(_ clipboard: FakeClipboard, now: Date? = nil) -> PasteboardWatcher {
        let instant = now ?? noon
        return PasteboardWatcher(source: clipboard, now: { instant })
    }

    // MARK: - Noticing

    @Test("notices a copy and works out what it was")
    func noticesACopy() async {
        let clipboard = FakeClipboard()
        clipboard.focus(on: "Safari")
        let watcher = watcher(clipboard)
        clipboard.write("https://example.com", from: "Safari")

        let clip = await watcher.newClip(at: noon)?.clip

        #expect(clip?.text == "https://example.com")
        #expect(clip?.kind == .link)
        #expect(clip?.source == "Safari")
        #expect(clip?.copiedAt == noon)
    }

    @Test("skips excluded bundle identifiers but records unknown and other applications")
    func excludesOnlySelectedApplications() async {
        let clipboard = FakeClipboard()
        clipboard.focus(on: "Private App", bundleIdentifier: "com.example.private")
        let watcher = watcher(clipboard)
        await watcher.setExcludedApplications(["com.example.private"])

        clipboard.write("secret copy", bundleIdentifier: "COM.EXAMPLE.PRIVATE")
        #expect(await watcher.newClip(at: noon) == nil)

        clipboard.write("ordinary copy", bundleIdentifier: "com.example.other")
        #expect(await watcher.newClip(at: noon) == nil)
        clipboard.write("ordinary copy", bundleIdentifier: "com.example.other")
        #expect(await watcher.newClip(at: noon)?.clip.text == "ordinary copy")

        clipboard.focus(on: nil)
        #expect(await watcher.newClip(at: noon) == nil)
        clipboard.write("unknown provenance")
        #expect(await watcher.newClip(at: noon)?.clip.text == "unknown provenance")
    }

    @Test("drops a copy when the frontmost application changes before polling")
    func excludesCopyWhenFocusChangesBeforePolling() async {
        let clipboard = FakeClipboard()
        clipboard.focus(on: "Private App", bundleIdentifier: "com.example.private")
        let watcher = watcher(clipboard)
        await watcher.setExcludedApplications(["com.example.private"])

        clipboard.write("private copy", from: "Private App", bundleIdentifier: "com.example.private")
        clipboard.focus(on: "Other App", bundleIdentifier: "com.example.other")

        #expect(await watcher.newClip(at: noon) == nil)
    }

    @Test("does not attribute a copy to an application after focus changes")
    func leavesSourceUnknownWhenFocusChangesBeforePolling() async throws {
        let clipboard = FakeClipboard()
        clipboard.focus(on: "Private App", bundleIdentifier: "com.example.private")
        let watcher = watcher(clipboard)

        clipboard.write("copy", from: "Private App", bundleIdentifier: "com.example.private")
        clipboard.focus(on: "Other App", bundleIdentifier: "com.example.other")

        let clip = try #require(await watcher.newClip(at: noon)?.clip)
        #expect(clip.source == nil)
    }

    @Test("records an escaped-quote named secret as hidden without changing the text")
    func escapedQuoteNamedSecretIsHidden() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let text = #"""
            {
              "password": "abc123\"def456",
              "enabled": true
            }
            """#
        clipboard.write(text, from: "Code")

        let clip = await watcher.newClip(at: noon)?.clip

        #expect(clip?.text == text)
        #expect(clip?.kind == .secret)
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

    /// A copy made while the Clipboard switch was off must not be kept when it is turned back on.
    @Test("passes over what was copied while it was not watching")
    func passOverSkipsTheCopyMadeWhileOff() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("copied while recording was off")

        await watcher.passOver(upTo: watcher.changeCount)

        #expect(await watcher.newClip(at: noon)?.clip == nil)
        clipboard.write("copied once it was back on")
        #expect(await watcher.newClip(at: noon)?.clip.text == "copied once it was back on")
    }

    @Test("a copy made after the baseline was read is still noticed")
    func passOverKeepsWhatCameAfterTheBaseline() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("copied while recording was off")
        let baseline = watcher.changeCount
        clipboard.write("copied just after it went back on")

        await watcher.passOver(upTo: baseline)

        #expect(await watcher.newClip(at: noon)?.clip.text == "copied just after it went back on")
    }

    @Test("forgets a write announced while recording was off")
    func passOverForgetsAnAnnouncement() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        watcher.ignoreNextWrite(of: "same words")

        await watcher.passOver(upTo: watcher.changeCount)
        clipboard.write("same words")

        #expect(await watcher.newClip(at: noon)?.clip.text == "same words")
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

    // MARK: - Too large to keep

    /// The classifier reads the whole string, so the bound is asked before it, not by the store after.
    @Test("says nothing about a copy too large to keep")
    func refusesAnOversizeCopyWithoutReadingIt() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write(String(repeating: "a", count: 3_000_000))

        #expect(await watcher.newClip(at: noon) == nil)
    }

    /// Both flavours count, the way `ClipboardStore.weight(of:)` counts them.
    @Test("counts the formatted flavour towards the bound")
    func theRichFormCountsTowardsTheBound() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(
            source: clipboard, budget: .standard.limiting(largestClip: 20), now: { noon })
        clipboard.write(String(repeating: "a", count: 11), html: String(repeating: "b", count: 11))

        #expect(await watcher.newClip(at: noon) == nil)
    }

    @Test("refuses plain text over the bound without reading its rich form")
    func oversizeTextSkipsTheHTML() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(
            source: clipboard, budget: .standard.limiting(largestClip: 20), now: { noon })
        clipboard.write(String(repeating: "a", count: 21), html: "<b>a</b>")

        #expect(await watcher.newClip(at: noon) == nil)
        #expect(clipboard.htmlReads == 0)
    }

    @Test("refuses a rich-only copy whose HTML alone is over the bound")
    func oversizeHTMLIsRefused() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(
            source: clipboard, budget: .standard.limiting(largestClip: 20), now: { noon })
        clipboard.write(nil, html: "<p>" + String(repeating: "a", count: 20) + "</p>")

        #expect(await watcher.newClip(at: noon) == nil)
        #expect(clipboard.htmlReads == 1)
    }

    @Test("notices a rich-only copy")
    func richOnlyCopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write(nil, html: "<p>Hello <b>world</b></p>")

        let noticed = await watcher.newClip(at: noon)

        #expect(noticed?.clip.text == "Hello world")
        #expect(noticed?.clip.richText == "<p>Hello <b>world</b></p>")
    }

    @Test("records a bounded plain form when deeply nested HTML expands past the clip limit")
    func deeplyNestedHTMLKeepsItsBoundedPlainForm() async throws {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write(nil, html: String(repeating: "<ul><li>x", count: 200_000))
        let clock = ContinuousClock()
        let start = clock.now

        let clip = try #require(await watcher.newClip(at: noon)?.clip)

        #expect(start.duration(to: clock.now) < .seconds(5))
        #expect(!clip.text.isEmpty)
        #expect(clip.text.utf8.count <= ClipboardBudget.standard.largestClip)
        #expect(clip.text.hasSuffix("…"))
        #expect(clip.richText == nil)
    }

    @Test("uses the watcher's output limit and keeps the bounded plain form")
    func richOnlyCopyUsesItsConfiguredOutputLimit() async throws {
        let clipboard = FakeClipboard()
        let html = String(repeating: "<ul><li>x", count: 20)
        let outputLimit = html.utf8.count
        let watcher = PasteboardWatcher(
            source: clipboard, budget: .standard.limiting(largestClip: outputLimit), now: { noon })
        clipboard.write(nil, html: html)

        let clip = try #require(await watcher.newClip(at: noon)?.clip)

        #expect(clip.text.utf8.count <= outputLimit)
        #expect(clip.text.hasSuffix("…"))
        #expect(clip.richText == nil)
    }

    @Test("records an RTF-only copy as plain text")
    func rtfOnlyCopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let rtf = Data(#"{\rtf1\ansi Hello \b world\b0}"#.utf8)
        clipboard.write(nil, rtf: rtf)

        #expect(await watcher.newClip(at: noon)?.clip.text == "Hello world")
    }

    @Test("refuses RTF over the single-clip bound before importing it")
    func oversizedRTFCopy() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(
            source: clipboard, budget: .standard.limiting(largestClip: 20), now: { noon })
        clipboard.write(nil, rtf: Data(repeating: 0x61, count: 21))

        #expect(await watcher.newClip(at: noon) == nil)
    }

    @Test("keeps a picture attached to copied text")
    func textAndPictureCopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let image = (data: Data([0x47, 0x49, 0x46]), width: 1, height: 1)
        clipboard.write("described picture", picture: image)

        let noticed = await watcher.newClip(at: noon)
        #expect(noticed?.clip.text == "described picture")
        #expect(noticed?.clip.kind != .image)
        #expect(noticed?.picture?.data == image.data)
    }

    @Test("records a picture-only copy")
    func pictureOnlyCopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write(nil, picture: (data: Data([0x47, 0x49, 0x46]), width: 1, height: 1))

        let noticed = await watcher.newClip(at: noon)
        #expect(noticed?.clip.kind == .image)
        #expect(noticed?.picture?.data == Data([0x47, 0x49, 0x46]))
    }

    @Test("records a picture when its RTF flavour has no text")
    func pictureWithEmptyRTF() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let image = (data: Data([0x47, 0x49, 0x46]), width: 1, height: 1)
        let rtf = Data(#"{\rtf1 }"#.utf8)
        clipboard.write(nil, rtf: rtf, picture: image)

        #expect(RichTextPlainForm.plainText(fromRTF: rtf) == "")
        let noticed = await watcher.newClip(at: noon)
        #expect(noticed?.clip.kind == .image)
        #expect(noticed?.picture?.data == image.data)
    }

    @Test("keeps meaningful RTF text when the copy also has a picture")
    func pictureWithRTFText() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let image = (data: Data([0x47, 0x49, 0x46]), width: 1, height: 1)
        clipboard.write(nil, rtf: Data(#"{\rtf1 Notes}"#.utf8), picture: image)

        let noticed = await watcher.newClip(at: noon)

        #expect(noticed?.clip.text == "Notes")
        #expect(noticed?.clip.kind != .image)
        #expect(noticed?.picture?.data == image.data)
    }

    @Test("ignores a rich-only copy that is blank as plain text")
    func blankRichOnlyCopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write(nil, html: "<p> </p>")

        #expect(await watcher.newClip(at: noon) == nil)
    }

    @Test("compares noticed pictures by bytes and dimensions")
    func noticedClipEqualityIncludesPictureDimensions() {
        let clip = Clip(text: "same", kind: .text, copiedAt: noon)
        let data = Data([1, 2, 3])
        let first = NoticedClip(clip: clip, picture: (data, 10, 20))
        let same = NoticedClip(clip: clip, picture: (data, 10, 20))
        let differentSize = NoticedClip(clip: clip, picture: (data, 20, 10))

        #expect(first == same)
        #expect(first != differentSize)
    }

    @Test("still notices a copy that fits")
    func keepsACopyUnderTheBound() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("small enough")

        #expect(await watcher.newClip(at: noon)?.clip.text == "small enough")
    }

    @Test("treats a bound of zero as no bound")
    func noBoundKeepsEverything() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(
            source: clipboard, budget: .standard.limiting(largestClip: 0), now: { noon })
        clipboard.write("kept whatever its length")

        #expect(await watcher.newClip(at: noon)?.clip.text == "kept whatever its length")
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

        let finishWrite = watcher.ignoreNextWrite(of: "copied by the user")
        finishWrite(clipboard.write("copied by the user"))

        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    /// The announcement comes before the write, because a tick lands between the two often enough.
    @Test("ignores the announced write even when a tick lands in the middle of it")
    func announcementCoversTheWrite() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        let finishWrite = watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        // A tick between the announcement and the write sees nothing and must not spend it.
        #expect(await watcher.newClip(at: noon)?.clip == nil)
        finishWrite(clipboard.write("pasted by Uttrflow"))

        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    @Test("keeps multiple announced writes until each reaches the clipboard")
    func multipleAnnouncementsSurviveBeforeOnePoll() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        let finishFirst = watcher.ignoreNextWrite(of: "first app paste")
        // A second asynchronous writer can announce before the first write lands.
        let finishSecond = watcher.ignoreNextWrite(of: "second app paste")
        finishFirst(clipboard.write("first app paste"))
        #expect(await watcher.newClip(at: noon) == nil)

        finishSecond(clipboard.write("second app paste"))
        #expect(await watcher.newClip(at: noon) == nil)

        clipboard.write("copied by the user")
        #expect(await watcher.newClip(at: noon)?.clip.text == "copied by the user")
    }

    /// The failure this prevents: a copy in the same tick as a paste never reaching the panel.
    @Test("a copy that lands in the same tick as an Uttrflow paste is still noticed")
    func aCopyRacingThePasteSurvives() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        let finishWrite = watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        finishWrite(clipboard.write("pasted by Uttrflow"))
        // Copied before the next tick, so one tick sees both changes.
        clipboard.write("copied by the user")

        #expect(await watcher.newClip(at: noon)?.clip.text == "copied by the user")
    }

    /// K4 — a picture write names the bytes it puts there, so it claims its own change and no later one.
    @Test("ignores the picture Uttrflow pasted, matched on its bytes")
    func ignoresAnnouncedPicture() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let pasted = Data([0x89, 0x50, 0x4E, 0x47])

        let finishWrite = watcher.ignoreNextPicture(pasted)
        finishWrite(clipboard.write(nil, picture: (data: pasted, width: 2, height: 2)))

        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    /// What matching on the count alone swallows: a copy of the user's own in the same tick as a picture paste.
    @Test("a copy that lands in the same tick as a picture paste is still noticed")
    func aCopyRacingThePicturePasteSurvives() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let pasted = Data([0x89, 0x50, 0x4E, 0x47])

        let finishWrite = watcher.ignoreNextPicture(pasted)
        finishWrite(clipboard.write(nil, picture: (data: pasted, width: 2, height: 2)))
        clipboard.write("copied by the user")

        #expect(await watcher.newClip(at: noon)?.clip.text == "copied by the user")
    }

    @Test("a picture the user copied is not the one Uttrflow announced")
    func anotherPictureIsStillNoticed() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        let finishWrite = watcher.ignoreNextPicture(Data([0x89, 0x50, 0x4E, 0x47]))
        finishWrite(clipboard.write(nil, picture: (data: Data([0x47, 0x49, 0x46]), width: 1, height: 1)))

        #expect(await watcher.newClip(at: noon)?.clip.kind == .image)
    }

    @Test("does not keep a concealed picture")
    func concealedPictureIsSkipped() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        clipboard.write(
            nil, picture: (data: Data([0x89, 0x50, 0x4E, 0x47]), width: 2, height: 2),
            marked: .concealed)

        #expect(await watcher.newClip(at: noon) == nil)
    }

    @Test("records a same-text copy after the announced write is refused")
    func refusedWriteDoesNotHideTheUsersCopy() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        let withdraw = watcher.ignoreNextWrite(of: "same words")
        withdraw(nil)
        clipboard.write("same words")

        #expect(await watcher.newClip(at: noon)?.clip.text == "same words")
    }

    @Test("still ignores its own write when the copy arrives first")
    func announcementSurvivesUntilItsOwnWriteArrives() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)

        let finishWrite = watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        clipboard.write("copied by the user")
        #expect(await watcher.newClip(at: noon)?.clip.text == "copied by the user")

        // Not spent by somebody else's copy, so Uttrflow's own write is still ignored.
        finishWrite(clipboard.write("pasted by Uttrflow"))
        #expect(await watcher.newClip(at: noon)?.clip == nil)
    }

    @Test("goes back to noticing copies after the announced write")
    func announcementIsSpentOnce() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let finishWrite = watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        finishWrite(clipboard.write("pasted by Uttrflow"))
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
        watcher.ignoreNextWrite(of: "pasted by Uttrflow")(nil)

        // Minutes later, after the failed write has withdrawn its reservation.
        let later = noon.addingTimeInterval(60)
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

        let finishWrite = watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        let soon = noon.addingTimeInterval(2)
        clock.withLock { $0 = soon }
        finishWrite(clipboard.write("pasted by Uttrflow"))

        #expect(await watcher.newClip(at: soon)?.clip == nil)
    }

    @Test("a delayed poll still ignores the exact write Uttrflow announced")
    func delayedPollIgnoresOwnWrite() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let finishWrite = watcher.ignoreNextWrite(of: "same words")
        let changeCount = clipboard.write("same words")
        finishWrite(changeCount)

        let later = noon.addingTimeInterval(2.5)
        #expect(await watcher.newClip(at: later) == nil)

        // Identical text from a newer generation is still a user copy.
        clipboard.write("same words")
        #expect(await watcher.newClip(at: later)?.clip.text == "same words")
    }

    @Test("a delayed poll does not record an app-owned concealed write as a secret clip")
    func delayedPollIgnoresConcealedOwnWrite() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let finishWrite = watcher.ignoreNextWrite(of: "same words")
        finishWrite(clipboard.write("same words", marked: .concealed))

        let later = noon.addingTimeInterval(2.5)
        #expect(await watcher.newClip(at: later) == nil)
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
        let finishWrite = watcher.ignoreNextWrite(of: "one")
        finishWrite(clipboard.write("one"))
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

    /// The panel catches up as it opens, so the poll is set by battery rather than by the gesture. See `Docs/performance-idle.md`.
    @Test("polls no more than twice a second")
    func interval() {
        #expect(PasteboardWatcher.pollInterval >= .milliseconds(500))
    }

    @Test("lets the system move a poll by a fifth of the interval, so it can coalesce wakeups")
    func tolerance() {
        #expect(PasteboardWatcher.tolerance(for: .milliseconds(500)) == .milliseconds(100))
        #expect(PasteboardWatcher.tolerance(for: .milliseconds(1)) < .milliseconds(1))
    }

    @Test("catches up on a copy made since the last poll, and hands it once")
    func catchUp() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        clipboard.write("copied a moment before the panel opened")
        let handed = Mutex<[String]>([])

        await watcher.catchUp { noticed in handed.withLock { $0.append(noticed.clip.text) } }

        #expect(handed.withLock { $0 } == ["copied a moment before the panel opened"])
        #expect(await watcher.newClip(at: noon) == nil)
    }

    @Test("hands nothing when catching up finds no new copy")
    func catchUpWithNothingNew() async {
        let clipboard = FakeClipboard()
        let watcher = watcher(clipboard)
        let handed = Mutex(0)

        await watcher.catchUp { _ in handed.withLock { $0 += 1 } }

        #expect(handed.withLock { $0 } == 0)
    }

    /// Matching uses the generation returned by the write, without needing a clock.
    @Test("matches the generation the write created")
    func defaultClock() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(source: clipboard)

        let finishWrite = watcher.ignoreNextWrite(of: "pasted by Uttrflow")
        finishWrite(clipboard.write("pasted by Uttrflow"))
        #expect(await watcher.newClip(at: Date()) == nil)

        clipboard.write("copied by the user")
        #expect(await watcher.newClip(at: Date())?.clip.text == "copied by the user")
    }
}
