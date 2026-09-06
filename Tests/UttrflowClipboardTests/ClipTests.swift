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
        #expect(clip("  padded  \nmore").summary == "padded")
        #expect(clip("").summary.isEmpty)
        #expect(clip("\n\nfirst real line").summary == "first real line")
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
}
