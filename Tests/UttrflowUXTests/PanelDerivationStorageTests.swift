// Holds source-version and optional-result behavior across the shared memo seam.
import Foundation
import Synchronization
import Testing
import UttrflowClipboard
@testable import UttrflowUX

@Suite("Panel derivation storage contracts")
struct PanelDerivationStorageTests {
    @Test("missing HTML leaves a remembered nil parse intact and plain text is not its version")
    func checklistNilAndMissingHTML() {
        let parses = Mutex(0)
        let memo = ChecklistProgresses { _ in
            parses.withLock { $0 += 1 }
            return nil
        }
        let clip = Clip(
            id: UUID(), text: "plain", kind: .text, copiedAt: PanelFixture.now, richText: "<p>plain</p>")
        #expect(memo.progress(of: clip) == nil)
        let absent = Clip(id: clip.id, text: "edited", kind: .text, copiedAt: clip.copiedAt)
        #expect(memo.progress(of: absent) == nil)
        let restored = Clip(
            id: clip.id, text: "edited", kind: .text, copiedAt: clip.copiedAt, richText: clip.richText)
        #expect(memo.progress(of: restored) == nil)
        #expect(parses.withLock { $0 } == 1)
        memo.prune(to: [])
        #expect(memo.progress(of: restored) == nil)
        #expect(parses.withLock { $0 } == 2)
    }

    @Test("a changed suffix beyond the bounded prefix invalidates a cached folding fallback")
    func fullTextVersionForBoundedFallback() {
        let folds = Mutex(0)
        let memo = FoldedTexts { _ in
            folds.withLock { $0 += 1 }
            return nil
        }
        let prefix = "a" + String(repeating: "\u{0301}", count: 100_000)
        let clip = PanelFixture.clip(prefix + "x")
        let changed = Clip(id: clip.id, text: prefix + "y", kind: clip.kind, copiedAt: clip.copiedAt)
        let bounded = String(SearchFolding.boundedPrefix(of: clip.text))
        #expect(memo.text(of: clip) == bounded)
        #expect(memo.text(of: clip) == bounded)
        #expect(folds.withLock { $0 } == 1)
        #expect(memo.text(of: changed) == bounded)
        #expect(folds.withLock { $0 } == 2)
    }
}
