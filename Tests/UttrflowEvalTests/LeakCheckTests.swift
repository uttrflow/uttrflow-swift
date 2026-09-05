// Tests the leak verdicts.
import Testing

@testable import UttrflowEval

@Suite("Leak check")
struct LeakCheckTests {
    private let megabyte: Int64 = 1_000_000

    private func check(_ megabytes: [Int64], allowance: Int64 = 32) -> LeakCheck {
        LeakCheck(
            footprints: megabytes.map { $0 * megabyte }, allowanceBytes: allowance * megabyte)
    }

    @Test("two readings cannot show a trend")
    func twoReadingsAreUndetermined() {
        #expect(check([100, 900]).verdict == .undetermined)
        #expect(check([]).verdict == .undetermined)
        #expect(check([]).growthBytes == 0)
        #expect(check([]).perDictationBytes == 0)
    }

    @Test("growth inside the allowance is clean")
    func settlingIsClean() {
        let leak = check([100, 104, 102, 110])
        #expect(leak.verdict == .clean)
        #expect(leak.passed)
        #expect(leak.growthBytes == 10 * megabyte)
        #expect(leak.perDictationBytes == 10 * megabyte / 3)
    }

    /// Memory that climbs at every repetition and never comes back is the finding the profile exists for.
    @Test("climbing at every repetition past the allowance is a leak")
    func monotonicGrowthIsALeak() {
        let leak = check([100, 130, 160, 190])
        #expect(leak.neverFellBack)
        #expect(leak.verdict == .leaking)
        #expect(leak.passed == false)
    }

    /// Growth that wobbles might be a long-lived cache settling, and only a longer run can tell.
    @Test("growth that fell back on the way is only suspect")
    func wobblingGrowthIsSuspect() {
        let leak = check([100, 200, 150, 190])
        #expect(leak.neverFellBack == false)
        #expect(leak.verdict == .suspect)
        #expect(leak.passed == false)
    }

    @Test("giving memory back is clean, and reported as negative growth")
    func shrinkingIsClean() {
        let leak = check([200, 180, 160])
        #expect(leak.growthBytes == -40 * megabyte)
        #expect(leak.perDictationBytes == -20 * megabyte)
        #expect(leak.verdict == .clean)
    }

    /// A flat run has not fallen back either, but it has not grown, so the allowance decides first.
    @Test("a flat run is clean despite never falling back")
    func flatIsClean() {
        let leak = check([100, 100, 100])
        #expect(leak.neverFellBack)
        #expect(leak.verdict == .clean)
    }

    @Test("the default allowance is stated in bytes, not implied")
    func defaultAllowance() {
        #expect(LeakCheck(footprints: []).allowanceBytes == LeakCheck.defaultAllowanceBytes)
        #expect(LeakCheck.defaultAllowanceBytes == 32 * 1024 * 1024)
    }
}
