// The diagnostics recorder counts pieces decoded without conditioning in a row.
import Testing
import UttrflowCore
import UttrflowUX

@Suite("Diagnostics conditioning run")
struct DiagnosticsConditioningTests {
    @Test("three unconditioned pieces in a row count three, and a conditioned one resets the run")
    func runCountsAndResets() async {
        let recorder = DiagnosticsRecorder()
        for _ in 0..<3 { await recorder.recordConditioning(.unavailable(.tokenizerUnavailable)) }
        #expect(await recorder.unconditionedRun == 3)
        #expect(await recorder.conditioning == .unavailable(.tokenizerUnavailable))
        await recorder.recordConditioning(.available)
        #expect(await recorder.unconditionedRun == 0)
    }
}
