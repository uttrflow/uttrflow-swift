import Testing

@testable import UttrflowCore

@Suite("Naming why a dictation was slow")
struct SlowDictationCauseTests {
    private let target = Duration.seconds(2)

    @Test("A wait that keeps to the target has no cause.")
    func keptWaitHasNoCause() {
        let cause = SlowDictationCause.of(
            wait: .seconds(2), target: target, spent: [.modelLoad: .seconds(9)], typical: [:])
        #expect(cause == nil)
    }

    @Test(
        "Each cause is named when it alone ran past its usual cost.",
        arguments: SlowDictationCause.allCases.filter { $0 != .other })
    func eachCauseIsNamed(cause: SlowDictationCause) {
        let named = SlowDictationCause.of(
            wait: .seconds(5), target: target, spent: [cause: .seconds(3)], typical: [:])
        #expect(named == cause)
    }

    @Test("The cause furthest past its usual cost wins, not the one that took longest.")
    func excessOverTypicalDecides() {
        let cause = SlowDictationCause.of(
            wait: .seconds(6), target: target,
            spent: [.contextRead: .seconds(4), .fallbackDecode: .seconds(2)],
            typical: [.contextRead: .milliseconds(3_800), .fallbackDecode: .zero])
        #expect(cause == .fallbackDecode)
    }

    @Test("A slow wait no cause accounts for is other.")
    func unaccountedWaitIsOther() {
        let cause = SlowDictationCause.of(
            wait: .seconds(5), target: target,
            spent: [.insertionConfirmation: .milliseconds(50)],
            typical: [.insertionConfirmation: .milliseconds(80)])
        #expect(cause == .other)
    }
}
