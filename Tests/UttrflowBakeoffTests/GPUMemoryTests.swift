// Tests that each gpu-memory pass line carries the settled process footprint.
import Testing
@testable import uttrflow_bakeoff

struct GPUMemoryTests {
    @Test("each pass line includes the sampled process footprint")
    func passLineReportsFootprint() {
        let line = GPUMemory.passLine(
            label: "pass 001 complete  200 ms", processorMilliseconds: 150,
            memory: "active  2500 MB  cache     0 MB  peak  3000 MB", footprintBytes: 3_072 * 1_048_576)

        #expect(line.contains("active  2500 MB  cache     0 MB  peak  3000 MB"))
        #expect(line.contains("footprint 3072 MB"))
    }

    @Test("a failed settled footprint read is visible")
    func passLineReportsUnavailableFootprint() {
        let line = GPUMemory.passLine(
            label: "pass 001 complete  200 ms", processorMilliseconds: 150,
            memory: "active  2500 MB  cache     0 MB  peak  3000 MB", footprintBytes: nil)

        #expect(line.hasSuffix("footprint unavailable"))
    }
}
