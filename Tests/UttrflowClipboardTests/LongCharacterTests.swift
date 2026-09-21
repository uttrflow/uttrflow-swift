// Tests that one enormous character cannot make classifying a clip quadratic (#896).

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("A clip holding one very long character")
struct LongCharacterTests {
    static let zalgo = "a" + String(repeating: "\u{0301}", count: 33_000)
    static let family = String(repeating: "👩\u{200D}", count: 10_000) + "👧"
    static let prose = String(repeating: "plain words and more words ", count: 2_700)

    @Test(
        "the boundary walks check a bounded number of positions, however long the character",
        arguments: [zalgo, family, prose + zalgo])
    func boundaryWalkIsBounded(_ text: String) {
        let tally = ScanTally()
        let kind = ClipBytes.$boundaryTally.withValue(tally) { ClipKindDetector.kind(of: text) }
        #expect(kind != .secret)
        #expect(tally.count < 2_000, "\(tally.count) boundary checks")
    }

    @Test("a boundary inside ordinary text is still a character boundary")
    func ordinaryTextIsCharacterAligned() {
        let text = "café au lait"
        let index = ClipBytes(text: text).character(atOrBefore: 4)
        #expect(text[..<index] == "caf")
    }
}
