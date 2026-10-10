// Tests for one clip's own rules.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("What one clip is")
struct ClipTests {
    private func clip(
        _ text: String = "hello", alias: String? = nil,
        category: String? = nil, pinned: Bool = false
    ) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: noon, alias: alias, category: category,
            isPinned: pinned)
    }

    /// Retention hangs on this: history ages out, and anything deliberately kept does not.
    @Test("counts as kept once the user has named, filed or pinned it")
    func keptness() {
        #expect(clip().isKept == false)
        #expect(clip(alias: "/pgprod").isKept)
        #expect(clip(category: "Credentials").isKept)
        #expect(clip(pinned: true).isKept)
    }

    /// Rows are scanned with the arrow keys, so a multi-line clip must not grow one.
    @Test("summarises to a single line")
    func summary() {
        #expect(clip("one\ntwo\nthree").summary == "one")
        #expect(clip("one\ntwo").additionalLineCount == 1)
        #expect(clip("").summary.isEmpty)
        #expect(clip("\n\nfirst real line").summary == "first real line")
        #expect(clip("\n\nfirst real line").additionalLineCount == 2)
    }

    @Test("caps a long first line")
    func summaryCap() {
        let text = String(repeating: "a", count: 400) + "\nignored"
        #expect(clip(text).summary == String(repeating: "a", count: 300))
    }

    @Test("shows the length when the first line is entirely whitespace")
    func whitespaceSummaryLength() {
        let text = String(repeating: " ", count: 400) + "\nnext"
        #expect(clip(text).summary == "Whitespace only · 405 characters")
        #expect(clip(text).additionalLineCount == 1)
    }

    @Test("bounds the complete preview and marks truncation")
    func previewCap() {
        let text = String(repeating: "x", count: Clip.previewCharacterLimit + 1)
        #expect(
            clip(text).preview == String(repeating: "x", count: Clip.previewCharacterLimit)
                + "\n… preview truncated")
    }

    @Test("trims leading and trailing whitespace from the first line")
    func summaryWhitespace() {
        #expect(clip("  padded  \nmore").summary == "padded")
    }

    @Test("stops at a CRLF line break")
    func summaryCRLF() {
        #expect(clip("first\r\nsecond").summary == "first")
        #expect(clip("first\r\nsecond").additionalLineCount == 1)
    }

    /// What goes back out must be exactly what came in; the summary is for display only.
    @Test("keeps the original text untouched however it is displayed")
    func textIsNotNormalised() {
        let messy = "  line one  \n\tline two\n"
        #expect(clip(messy).text == messy)
    }

    @Test("round-trips through Codable with every field")
    func codable() throws {
        let original = Clip(
            text: "postgres://…", kind: .secret, copiedAt: noon, source: "TablePlus",
            alias: "/pgprod", category: "Credentials", isPinned: true)
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    /// A kind that this build does not know about still decodes, so a future clip never breaks older releases.
    @Test("defaults an unknown kind to text")
    func unknownKindBecomesText() throws {
        let payload = #"""
            {"id":"00000000-0000-0000-0000-00000000000a","text":"hello","kind":"table","copiedAt":1700000000.0,"lastUsedAt":1700000000.0,"lastUsedOrder":0,"timesCopied":1,"origin":"copied","dictations":[],"isPinned":false}
            """#
        let clip = try JSONDecoder().decode(Clip.self, from: Data(payload.utf8))
        #expect(clip.kind == .text)
        #expect(clip.text == "hello")
    }

    /// Same shape for the origin field.
    @Test("defaults an unknown origin to copied")
    func unknownOriginBecomesCopied() throws {
        let payload = #"""
            {"id":"00000000-0000-0000-0000-00000000000b","text":"hello","kind":"text","copiedAt":1700000000.0,"lastUsedAt":1700000000.0,"lastUsedOrder":0,"timesCopied":1,"origin":"borrowed","dictations":[],"isPinned":false}
            """#
        let clip = try JSONDecoder().decode(Clip.self, from: Data(payload.utf8))
        #expect(clip.origin == .copied)
    }
}
