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

/// ``SampleAccumulator/peakLevel`` is a high-water mark and never falls, which is what
/// makes it right for asking afterwards whether the microphone was muted and wrong for
/// drawing a meter — one loud syllable would peg the bars for the rest of the recording.
/// The momentary level is the one the floating button reads.
@Suite("The momentary level")
struct MomentaryLevelTests {
    @Test("is zero before anything is heard")
    func startsAtZero() {
        #expect(SampleAccumulator().momentaryLevel == 0)
    }

    @Test("is the block's root mean square, not its peak")
    func isRootMeanSquare() {
        let accumulator = SampleAccumulator()

        // One loud sample among sixteen quiet ones. A peak meter reads 1; the ear, and
        // this, read something much smaller.
        accumulator.append([1] + Array(repeating: 0, count: 15))

        #expect(accumulator.peakLevel == 1)
        #expect(abs(accumulator.momentaryLevel - 0.25) < 0.0001)
    }

    /// The difference that matters: this one comes back down.
    @Test("falls between blocks, where the peak does not")
    func fallsWhenQuiet() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.8, count: 64))
        let loud = accumulator.momentaryLevel

        accumulator.append(Array(repeating: 0, count: 64))

        #expect(accumulator.momentaryLevel < loud)
        #expect(accumulator.peakLevel == 0.8)
    }

    /// Gradually, though. A meter that dropped to nothing in one block would flicker at
    /// every gap between syllables.
    @Test("falls gradually rather than cutting out")
    func fallsGradually() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.8, count: 64))

        accumulator.append(Array(repeating: 0, count: 64))

        #expect(accumulator.momentaryLevel > 0.4)
    }

    @Test("rises the moment a louder block arrives")
    func attackIsImmediate() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.1, count: 64))

        accumulator.append(Array(repeating: 0.9, count: 64))

        #expect(abs(accumulator.momentaryLevel - 0.9) < 0.0001)
    }

    @Test("a block of broken samples cannot produce a broken level")
    func survivesNonFinite() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.5, count: 8))

        accumulator.append([.nan, .infinity, -.infinity, .nan])

        #expect(accumulator.momentaryLevel.isFinite)
    }

    @Test("a finished recording cannot leak its level into the next one")
    func resetClearsIt() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.7, count: 32))

        accumulator.reset()

        #expect(accumulator.momentaryLevel == 0)
    }

    @Test("taking the samples clears it too")
    func takeClearsIt() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.7, count: 32))

        _ = accumulator.take()

        #expect(accumulator.momentaryLevel == 0)
    }
}

@Suite("SampleAccumulator: snapshot")
struct SampleAccumulatorSnapshotTests {
    @Test("copies what has been collected and leaves it in place")
    func snapshotLeavesBuffer() {
        let accumulator = SampleAccumulator()
        accumulator.append([0.1, 0.2])

        #expect(accumulator.snapshot == [0.1, 0.2])
        #expect(accumulator.count == 2)
        #expect(accumulator.take() == [0.1, 0.2])
    }
}
