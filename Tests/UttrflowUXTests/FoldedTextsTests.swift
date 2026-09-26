// Tests that a clip's text is folded for search once per text, and that search still matches it.
import Foundation
import Synchronization
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("The quick panel: folded clip text is remembered")
struct FoldedTextsTests {
    static let clips = [
        PanelFixture.clip("line one\nline two", minutesAgo: 1),
        PanelFixture.clip("tab\tseparated  and spaced", minutesAgo: 2),
        PanelFixture.clip("don\u{2019}t stop", minutesAgo: 3),
        PanelFixture.clip("plain text", minutesAgo: 4),
    ]

    @Test("two scans over the same clips fold each clip once")
    func foldsOnce() {
        let folds = Atomic<Int>(0)
        let memo = FoldedTexts { text in
            folds.add(1, ordering: .relaxed)
            return SearchFolding.folded(text)
        }
        let first = Self.clips.map { memo.text(of: $0) }
        let second = Self.clips.map { memo.text(of: $0) }

        #expect(first == second)
        #expect(first == ["line one line two", "tab separated and spaced", "don't stop", "plain text"])
        #expect(folds.load(ordering: .relaxed) == Self.clips.count)
    }

    @Test("a clip whose text changed is folded again")
    func refoldsChangedText() {
        let memo = FoldedTexts()
        let clip = PanelFixture.clip("one\ntwo", minutesAgo: 1)
        _ = memo.text(of: clip)
        let edited = Clip(
            id: clip.id, text: "three\u{2014}four", kind: clip.kind, copiedAt: clip.copiedAt)

        #expect(memo.text(of: edited) == "three-four")
    }

    @Test(
        "typed keyboard text still finds line breaks, curly quotes and dashes",
        arguments: [
            ("one line", 0), ("don't", 2), ("separated and", 1),
        ])
    func stillMatches(query: String, index: Int) {
        var panel = PanelFixture.panel(Self.clips)
        for _ in 0..<2 {
            panel = panel.applying(.search(query)).state
            #expect(panel.results.rows.map(\.id) == [Self.clips[index].id])
            panel = panel.applying(.search("")).state
        }
    }
}
