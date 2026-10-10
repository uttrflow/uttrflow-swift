// Tests the cheap BIP-39 candidate scan before recovery-phrase parsing.

import Testing

@testable import UttrflowCore

@Suite("BIP-39 scans are skipped for prose and bounded by the clipboard limit")
struct BIP39RecoveryPhraseScalingTests {
    static let largestClip = 2_000_000

    @Test("a two-megabyte prose clip never reaches the allocating phrase parser")
    func largeProseSkipsPhraseParsing() {
        let unit = "This is ordinary prose with nothing useful. "
        let repeats = Self.largestClip / unit.utf8.count
        let text =
            String(repeating: unit, count: repeats)
            + String(repeating: " ", count: Self.largestClip - repeats * unit.utf8.count)
        let prefilter = ScanTally()
        let candidates = ScanTally()

        let matches = BIP39RecoveryPhrase.$prefilterTally.withValue(prefilter) {
            BIP39RecoveryPhrase.$candidateTally.withValue(candidates) {
                BIP39RecoveryPhrase.matches(text)
            }
        }

        #expect(!matches)
        #expect(prefilter.count == Self.largestClip)
        #expect(candidates.count == 0)
    }

    @Test("a two-megabyte repeated wordlist run stays within the clip-byte bound")
    func repeatedWordlistIsBounded() {
        let text = String(repeating: "abandon ", count: Self.largestClip / 8)
        let prefilter = ScanTally()
        let candidates = ScanTally()

        BIP39RecoveryPhrase.$prefilterTally.withValue(prefilter) {
            BIP39RecoveryPhrase.$candidateTally.withValue(candidates) {
                _ = BIP39RecoveryPhrase.matches(text)
            }
        }

        #expect(text.utf8.count == Self.largestClip)
        #expect(prefilter.count == Self.largestClip)
        #expect(candidates.count <= Self.largestClip)
    }
}
