import Foundation
import Testing

@testable import UttrflowClipboard

/// E — a formatted clip has two representations, and every path has to say which one it
/// is using. These pin the one rule that makes the rest safe: the plain form is stored,
/// not derived.
@Suite("E · a clip that carries formatting")
struct ClipRichTextTests {
    static let now = Date(timeIntervalSince1970: 1_750_000_800)

    @Test("a clip says whether it has formatting")
    func saysSo() {
        let plain = Clip(text: "hello", kind: .text, copiedAt: Self.now)
        let note = Clip(text: "hello", kind: .text, copiedAt: Self.now, richText: "<b>hello</b>")

        #expect(!plain.isFormatted)
        #expect(note.isFormatted)
    }

    /// The rule the whole feature rests on. `text` is captured, never converted from the
    /// rich form — so a clip is pasteable into a terminal without anything having to run
    /// first, and the conversion that can fail never stands between the user and their
    /// words.
    @Test("the plain form is stored, not derived from the rich one")
    func plainIsStored() {
        let note = Clip(
            text: "Release checklist", kind: .text, copiedAt: Self.now,
            richText: "<h1>Release checklist</h1>")

        #expect(note.text == "Release checklist")
        #expect(!note.text.contains("<"), "never a tag, whatever the rich form holds")
        #expect(note.summary == "Release checklist")
    }

    /// A clip written before the field existed still loads. There are clipboards on disk
    /// with no `richText` in them, and a decoder that refused would empty somebody's
    /// history on the first launch after an update.
    @Test("a clip that predates formatting decodes as plain")
    func oldClipsDecode() throws {
        let old = """
            {"id":"1E30555C-3E63-4D24-837A-DF251ADC876E","text":"x",
             "kind":"text","copiedAt":1,"isPinned":false}
            """

        let clip = try JSONDecoder().decode(Clip.self, from: Data(old.utf8))

        #expect(clip.richText == nil)
        #expect(!clip.isFormatted)
    }

    @Test("and a formatted one survives a round trip")
    func roundTrips() throws {
        let note = Clip(
            text: "a note", kind: .text, copiedAt: Self.now, richText: "<ul><li>a note</li></ul>")

        let back = try JSONDecoder().decode(
            Clip.self, from: JSONEncoder().encode(note))

        #expect(back.richText == "<ul><li>a note</li></ul>")
        #expect(back.text == "a note")
    }
}

/// The watcher takes both flavours in one tick, or the two would describe different
/// moments of the clipboard.
@Suite("E · capturing both forms at once")
struct PasteboardRichCaptureTests {
    @Test("a copy with formatting keeps both, and one without keeps only the plain form")
    func capturesBoth() async {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(source: clipboard, now: { Date() })

        clipboard.write("Release checklist", html: "<h1>Release checklist</h1>")
        let formatted = await watcher.newClip(at: Date())?.clip

        clipboard.write("just words")
        let plain = await watcher.newClip(at: Date())?.clip

        #expect(formatted?.richText == "<h1>Release checklist</h1>")
        #expect(formatted?.text == "Release checklist")
        #expect(plain?.richText == nil)
        #expect(plain?.isFormatted == false)
    }
}
