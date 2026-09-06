import Testing

@testable import UttrflowPredict

@Suite("Trimming without Foundation")
struct WhitespaceTests {
    @Test("Trimming leaves a string that was already trimmed alone.")
    func trimmingIsIdempotent() {
        #expect(Whitespace.trimmed("main") == "main")
        #expect(Whitespace.trimmed("  main \t ") == "main")
        #expect(Whitespace.trimmed("   ") == "")
    }
}
