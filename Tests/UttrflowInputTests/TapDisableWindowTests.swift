import Testing

@testable import UttrflowInput

@Suite("Re-enabling a tap the system keeps disabling")
struct TapDisableWindowTests {
    private let second: UInt64 = 1_000_000_000

    @Test("The first disable is always re-enabled.")
    func firstIsReEnabled() {
        let result = TapDisableWindow.decide(last: 0, now: 5 * second, count: 0)
        #expect(result.reEnable)
        #expect(result.count == 1)
    }

    @Test("Two disables close together give up, so a genuine fault does not loop forever.")
    func twoCloseTogetherGiveUp() {
        let first = TapDisableWindow.decide(last: 0, now: 10 * second, count: 0)
        let next = TapDisableWindow.decide(
            last: 10 * second, now: 11 * second, count: first.count)
        #expect(!next.reEnable)
    }

    @Test("Two disables far apart both re-enable, so sleep and wake do not add up to a fault.")
    func twoFarApartBothReEnable() {
        let first = TapDisableWindow.decide(last: 0, now: 10 * second, count: 0)
        // A day later: outside the window, so the count restarts and the tap comes back.
        let later = 10 * second + 86_400 * second
        let next = TapDisableWindow.decide(last: 10 * second, now: later, count: first.count)
        #expect(next.reEnable)
        #expect(next.count == 1)
    }
}
