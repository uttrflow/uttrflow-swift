// Tests that a copy landing while the watcher reads a later flavour is never recorded as part of the copy before it (#2085).

import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowClipboard

/// A clipboard whose next copy lands the moment the watcher asks for a picture or for HTML.
private final class MidTickSource: ClipboardProvenanceSource, Sendable {
    /// One copy as the clipboard holds it.
    struct Copy {
        var text: String?
        var html: String?
        var picture: (data: Data, width: Int, height: Int)?
        var markers: PasteboardMarkers = []
        var writerBundleIdentifier: String?
        var isRemote = false
    }

    /// The flavour whose read lets the armed copy land.
    enum Trigger { case picture, html }

    private struct State {
        var count = 0
        var current = Copy()
        var landing: (copy: Copy, on: Trigger)?
    }

    private let state = Mutex(State())

    /// Copies as another application would: the contents change and the count goes up.
    func copy(_ copy: Copy) {
        state.withLock {
            $0.count += 1
            $0.current = copy
        }
    }

    /// Arms `copy` to land, with the count moving, when the watcher next reads `trigger`.
    func land(_ copy: Copy, whenReading trigger: Trigger) {
        state.withLock { $0.landing = (copy, trigger) }
    }

    /// Lands whatever is armed for `trigger`, then answers from the clipboard as it is now.
    private func reading<Value>(_ trigger: Trigger, _ flavour: (Copy) -> Value) -> Value {
        state.withLock { held in
            if let landing = held.landing, landing.on == trigger {
                held.landing = nil
                held.count += 1
                held.current = landing.copy
            }
            return flavour(held.current)
        }
    }

    func changeCount() -> Int { state.withLock(\.count) }
    func text() -> String? { state.withLock(\.current.text) }
    func html() -> String? { reading(.html, \.html) }
    func markers() -> PasteboardMarkers { state.withLock(\.current.markers) }
    func clipboardProvenance() -> ClipboardProvenance {
        state.withLock {
            ClipboardProvenance(
                markers: $0.current.markers,
                writerBundleIdentifier: $0.current.writerBundleIdentifier,
                isRemote: $0.current.isRemote)
        }
    }
    func image() -> (data: Data, width: Int, height: Int)? { reading(.picture, \.picture) }
    func frontmostApplicationName() -> String? { nil }
}

@Suite("A copy that lands between the watcher's reads")
struct MidTickWriteTests {
    private let ordinary = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
    private let concealed = Data([0x89, 0x50, 0x4E, 0x47, 0x02])

    @Test("a concealed picture landing during the picture read is never recorded, then or on the next tick")
    func concealedPictureMidTick() async {
        let source = MidTickSource()
        let watcher = PasteboardWatcher(source: source)
        source.copy(.init(picture: (ordinary, 1, 1)))
        source.land(.init(picture: (concealed, 1, 1), markers: [.concealed]), whenReading: .picture)

        let first = await watcher.newClip(at: Date())
        #expect(first == nil, "a picture read after the count moved was recorded")
        #expect(await watcher.newClip(at: Date()) == nil)
    }

    @Test("HTML landing during the HTML read is never kept as the earlier copy's rich text")
    func htmlMidTick() async throws {
        let source = MidTickSource()
        let watcher = PasteboardWatcher(source: source)
        source.copy(.init(text: "first copy", html: "<p>first copy</p>"))
        source.land(.init(text: "second copy", html: "<p>second copy</p>"), whenReading: .html)

        #expect(await watcher.newClip(at: Date()) == nil, "one copy's text was paired with another's HTML")
        let next = try #require(await watcher.newClip(at: Date()))
        #expect(next.clip.text == "second copy")
        #expect(next.clip.richText == "<p>second copy</p>")
    }

    @Test("a copy nothing lands on is still noticed whole")
    func undisturbedCopy() async throws {
        let source = MidTickSource()
        let watcher = PasteboardWatcher(source: source)
        source.copy(.init(text: "first copy", html: "<p>first copy</p>"))
        let clip = try #require(await watcher.newClip(at: Date()))
        #expect(clip.clip.richText == "<p>first copy</p>")
    }
}
