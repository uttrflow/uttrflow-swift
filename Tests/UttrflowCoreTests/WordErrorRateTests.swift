import Testing

@testable import UttrflowCore

/// Worked examples first, properties second.
///
/// Every rate in these tests was counted by hand before it was run, because a word
/// error rate is the one number in this project that cannot be sanity-checked by
/// looking at it: 12% and 21% are equally plausible-looking and only one of them is
/// what the recogniser did.
@Suite("Word error rate")
struct WordErrorRateTests {
    private func measure(_ reference: String, _ hypothesis: String) -> WordErrorRate {
        .measure(
            reference: reference.split(separator: " ").map(String.init),
            hypothesis: hypothesis.split(separator: " ").map(String.init)
        )
    }

    /// One word swapped for another: 1 error over 6 reference words.
    @Test("counts a substitution")
    func substitution() {
        let rate = measure("the cat sat on the mat", "the cat sat on a mat")
        #expect(rate.substitutions == 1)
        #expect(rate.deletions == 0)
        #expect(rate.insertions == 0)
        #expect(rate.hits == 5)
        #expect(rate.referenceWordCount == 6)
        #expect(rate.rate == 1.0 / 6.0)
    }

    /// A word the recogniser never produced: 1 error over 5.
    @Test("counts a deletion")
    func deletion() {
        let rate = measure("the quick brown fox jumps", "the quick fox jumps")
        #expect(rate.deletions == 1)
        #expect(rate.substitutions == 0)
        #expect(rate.insertions == 0)
        #expect(rate.referenceWordCount == 5)
        #expect(rate.hypothesisWordCount == 4)
        #expect(rate.rate == 1.0 / 5.0)
        #expect(rate.alignment.contains(.deletion("brown")))
    }

    /// A word nobody said: 1 error over 2, so 50% — insertions are divided by the
    /// reference length, not by the transcript's.
    @Test("counts an insertion")
    func insertion() {
        let rate = measure("ship it", "ship it now")
        #expect(rate.insertions == 1)
        #expect(rate.referenceWordCount == 2)
        #expect(rate.rate == 0.5)
        #expect(rate.alignment.contains(.insertion("now")))
    }

    /// One deletion and one insertion, not three substitutions: the cheapest path is
    /// two edits, and a scorer that took the diagonal every time would report 3/7.
    @Test("finds the cheapest alignment when edits could be counted several ways")
    func mixedEdits() {
        let rate = measure("i would like a cup of coffee", "i would like cup of hot coffee")
        #expect(rate.deletions == 1)
        #expect(rate.insertions == 1)
        #expect(rate.substitutions == 0)
        #expect(rate.errors == 2)
        #expect(rate.rate == 2.0 / 7.0)
    }

    /// A hallucinating engine is more than 100% wrong, and clamping that to 1 would hide
    /// the worst failure the product can have.
    @Test("allows a rate above one")
    func aboveOne() {
        let rate = measure("hello", "hello there my old friend")
        #expect(rate.insertions == 4)
        #expect(rate.rate == 4.0)
    }

    @Test("scores an exact transcript at zero")
    func perfect() {
        let rate = measure("the build passed", "the build passed")
        #expect(rate.rate == 0)
        #expect(rate.errors == 0)
        #expect(rate.hits == 3)
    }

    /// Hearing nothing is a complete deletion, which is exactly 100% and not a special case.
    @Test("scores an empty transcript at one")
    func heardNothing() {
        let rate = measure("the build passed", "")
        #expect(rate.deletions == 3)
        #expect(rate.rate == 1)
    }

    /// A rate needs a denominator. Reporting 0% for an empty reference would be a lie in
    /// the flattering direction.
    @Test("has no rate when there is no reference")
    func noReference() {
        #expect(measure("", "").rate == nil)
        #expect(measure("", "words appeared").rate == nil)
        #expect(measure("", "words appeared").insertions == 2)
    }

    @Test("counts each kind of operation separately")
    func countsByKind() {
        let rate = measure("a b c", "a x c d")
        #expect(rate.count(of: .match) == 2)
        #expect(rate.count(of: .substitution) == 1)
        #expect(rate.count(of: .insertion) == 1)
        #expect(rate.count(of: .deletion) == 0)
        #expect(rate.alignment.map(\.kind) == [.match, .substitution, .match, .insertion])
    }

    /// The whole point of keeping the alignment: a rate says a passage went badly and
    /// only this says which words.
    /// Three examples with only one cheapest alignment each, so what is asserted is the
    /// diff itself rather than the tie-break below.
    @Test("says which words went wrong")
    func alignmentReadsAsADiff() {
        #expect(
            measure("tell priya today", "tell preeya today").alignment == [
                .match("tell"), .substitution(reference: "priya", hypothesis: "preeya"),
                .match("today"),
            ])
        #expect(
            measure("tell priya today", "tell today").alignment == [
                .match("tell"), .deletion("priya"), .match("today"),
            ])
        #expect(
            measure("tell priya today", "tell priya again today").alignment == [
                .match("tell"), .match("priya"), .insertion("again"), .match("today"),
            ])
    }

    /// When two alignments cost the same, the diagonal wins. "Send it to priya" heard as
    /// "send to preeya now" is three edits either way — a deletion, a substitution and an
    /// insertion, or three substitutions — and this is the one it reports. The total is
    /// what the rate is made of and it is the same both ways; only the S/D/I breakdown
    /// depends on the preference, which is why the preference is fixed and written down
    /// rather than left to whichever path the search happened to reach first.
    @Test("prefers substitutions when two alignments cost the same")
    func tiedAlignmentsPreferTheDiagonal() {
        let rate = measure("send it to priya", "send to preeya now")
        #expect(rate.errors == 3)
        #expect(rate.substitutions == 3)
        #expect(rate.deletions == 0)
        #expect(rate.insertions == 0)
    }

    /// Summing errors and words, not averaging rates. The short passage here is 100%
    /// wrong and the long one is perfect; averaging the two rates would report 50%,
    /// which describes neither the corpus nor anything else.
    @Test("combines passages by summing, not by averaging rates")
    func combinesByTotal() {
        let short = measure("yes", "no")
        let long = measure(
            "one two three four five six seven eight nine", "one two three four five six seven eight nine")
        let combined = WordErrorRate.combined([short, long])
        #expect(combined.referenceWordCount == 10)
        #expect(combined.errors == 1)
        #expect(combined.rate == 0.1)
    }

    @Test("combines nothing into a rate of nothing")
    func combinesEmpty() {
        #expect(WordErrorRate.combined([]).rate == nil)
    }

    /// The split between kinds is decided by the backtrace's preference order. It cannot
    /// change the total, but it must not change between runs either, or two identical
    /// runs would report different tables.
    @Test("splits a tie the same way every time")
    func deterministicTieBreak() {
        let first = measure("a b", "c d")
        let second = measure("a b", "c d")
        #expect(first == second)
        #expect(first.substitutions == 2)
        #expect(first.rate == 1)
    }
}
