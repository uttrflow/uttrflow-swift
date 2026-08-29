import Testing

@testable import UttrflowAudio

@Suite("SampleAccumulator")
struct SampleAccumulatorTests {
    @Test("collects blocks in the order they arrive")
    func collectsInOrder() {
        let accumulator = SampleAccumulator()
        accumulator.append([0.1, 0.2])
        accumulator.append([0.3])

        #expect(accumulator.count == 3)
        #expect(accumulator.take() == [0.1, 0.2, 0.3])
    }

    @Test("ignores an empty block rather than counting it")
    func ignoresEmptyBlock() {
        let accumulator = SampleAccumulator()
        accumulator.append([])
        #expect(accumulator.count == 0)
        #expect(accumulator.peakLevel == 0)
    }

    @Test("tracks the loudest sample regardless of sign")
    func tracksPeak() {
        let accumulator = SampleAccumulator()
        accumulator.append([0.2, -0.8, 0.5])
        #expect(accumulator.peakLevel == 0.8)
    }

    @Test("keeps the highest peak once it has been seen")
    func peakDoesNotDecay() {
        let accumulator = SampleAccumulator()
        accumulator.append([0.9])
        accumulator.append([0.1])
        #expect(accumulator.peakLevel == 0.9)
    }

    @Test("ignores a non-finite sample instead of pinning the meter")
    func ignoresNonFinite() {
        let accumulator = SampleAccumulator()
        accumulator.append([.infinity, .nan, 0.3])
        #expect(accumulator.peakLevel == 0.3)
    }

    @Test("empties itself when taken, so one recording cannot leak into the next")
    func takeClears() {
        let accumulator = SampleAccumulator()
        accumulator.append([0.5])

        #expect(accumulator.take() == [0.5])
        #expect(accumulator.count == 0)
        #expect(accumulator.peakLevel == 0)
        #expect(accumulator.take().isEmpty)
    }

    @Test("discards everything on reset, peak included")
    func reset() {
        let accumulator = SampleAccumulator()
        accumulator.append([0.7, 0.2])
        accumulator.reset()

        #expect(accumulator.count == 0)
        #expect(accumulator.peakLevel == 0)
    }

    @Test("loses nothing when blocks arrive from several threads at once")
    func concurrentAppendsAreSafe() async {
        let accumulator = SampleAccumulator()
        let blocks = 200
        let perBlock = 16

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<blocks {
                group.addTask { accumulator.append(Array(repeating: 0.25, count: perBlock)) }
            }
        }

        #expect(accumulator.count == blocks * perBlock)
        #expect(accumulator.peakLevel == 0.25)
    }
}
