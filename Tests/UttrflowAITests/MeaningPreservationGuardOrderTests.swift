import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// The order the guard runs its checks in, seen through which kind a rewrite failing two of them is refused for.
@Suite("MeaningPreservationGuard check order")
struct MeaningPreservationGuardOrderTests {
    /// The guard under test.
    private let sut = MeaningPreservationGuard()

    /// The kind a rewrite is refused for, or nil when it is accepted.
    private func kind(_ original: String, _ rewritten: String) -> RefusalKind? {
        guard case .rejected(_, let kind) = sut.verdict(original: original, rewritten: rewritten) else {
            return nil
        }
        return kind
    }

    @Test("the text check runs before the layout check")
    func textBeforeLayout() {
        #expect(kind("first line\n\nsecond line", "Here is: first line second line.") == .preamble)
    }

}
