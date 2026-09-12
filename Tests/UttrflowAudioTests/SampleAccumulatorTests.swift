// Tests sample collection and the level meter.
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

/// The momentary level is what the floating button reads; the peak never falls. See Docs/audio-capture.md.
@Suite("The momentary level")
struct MomentaryLevelTests {
    @Test("is zero before anything is heard")
    func startsAtZero() {
        #expect(SampleAccumulator().momentaryLevel == 0)
    }

    @Test("is the block's root mean square, not its peak")
    func isRootMeanSquare() {
        let accumulator = SampleAccumulator()

        // One loud sample among sixteen quiet ones: a peak meter reads 1, the ear reads much less.
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

    /// A meter that dropped to nothing in one block would flicker at every gap between syllables.
    @Test("falls gradually rather than cutting out")
    func fallsGradually() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.8, count: 64))

        accumulator.append(Array(repeating: 0, count: 64))

        #expect(accumulator.momentaryLevel > 0.4)
    }

    /// A microphone that died stops appending, and a level only blocks can lower would hold its last reading.
    @Test("falls when no block arrives at all, so a dead microphone reads as silence")
    func fallsWithoutBlocks() {
        let accumulator = SampleAccumulator()
        accumulator.append(Array(repeating: 0.8, count: 64))

        let first = accumulator.momentaryLevel
        let second = accumulator.momentaryLevel

        #expect(second < first)
        for _ in 0..<40 { _ = accumulator.momentaryLevel }
        #expect(accumulator.momentaryLevel < 0.001)
    }

    /// The release belongs to reads that heard nothing, so a meter cannot quieten a microphone that is talking.
    @Test("does not fall on the read that follows a block")
    func holdsWhenABlockArrived() {
        let accumulator = SampleAccumulator()

        for _ in 0..<5 {
            accumulator.append(Array(repeating: 0.5, count: 64))
            #expect(abs(accumulator.momentaryLevel - 0.5) < 0.0001)
        }
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

    @Test("reads back every sample across many blocks, in order")
    func snapshotSpansBlocks() {
        let accumulator = SampleAccumulator()
        let total = SampleAccumulator.blockSize * 3 + 7
        for start in stride(from: 0, to: total, by: 1000) {
            let end = Swift.min(start + 1000, total)
            accumulator.append((start..<end).map { Float($0) / Float(total) })
        }

        let snapshot = accumulator.snapshot
        #expect(snapshot.count == total)
        #expect(snapshot == (0..<total).map { Float($0) / Float(total) })
    }

    @Test("takes a block-spanning recording whole and leaves nothing behind")
    func takeSpansBlocks() {
        let accumulator = SampleAccumulator()
        let total = SampleAccumulator.blockSize * 2 + 3
        accumulator.append(Array(repeating: 0.5, count: total))

        #expect(accumulator.take() == Array(repeating: 0.5, count: total))
        #expect(accumulator.count == 0)
        #expect(accumulator.snapshot.isEmpty)
    }

    @Test("accepts a single block larger than the storage block")
    func appendLargerThanBlock() {
        let accumulator = SampleAccumulator()
        let total = SampleAccumulator.blockSize * 2 + 5
        accumulator.append(Array(repeating: 0.25, count: total))

        #expect(accumulator.count == total)
        #expect(accumulator.snapshot.count == total)
    }
}

/// Reading the audio while it grows must not charge the capture thread for the read. See Docs/audio-capture.md.
@Suite("SampleAccumulator: reading while the capture thread writes")
struct SampleAccumulatorPrefixTests {
    @Test("the capture thread copies nothing, however often the audio is read")
    func readsDoNotCopyTheBuffer() {
        let accumulator = SampleAccumulator()
        let block = Array(repeating: Float(0.4), count: 1024)
        // Held across the next append, which is what the pipeline does with what `capturedSoFar()` returns.
        var held: [Float] = []
        for _ in 0..<400 {
            accumulator.append(block)
            held = accumulator.snapshot
        }

        #expect(held.count == 400 * 1024)
        #expect(accumulator.count == 400 * 1024)
        #expect(accumulator.copiedOnAppend == 0)
    }

    @Test("a prefix already read stays what it was while more audio arrives")
    func prefixSurvivesLaterAppends() async {
        let accumulator = SampleAccumulator()
        let first = SampleAccumulator.blockSize * 2 + 11
        accumulator.append((0..<first).map { Float($0) })
        let prefix = accumulator.snapshot

        await withTaskGroup(of: Void.self) { group in
            for round in 0..<50 {
                group.addTask {
                    accumulator.append(Array(repeating: Float(-round), count: 997))
                }
            }
        }

        #expect(prefix == (0..<first).map { Float($0) })
        #expect(accumulator.count == first + 50 * 997)
        #expect(Array(accumulator.snapshot.prefix(first)) == prefix)
        #expect(accumulator.copiedOnAppend == 0)
    }

    @Test("a read racing the capture thread never sees a torn prefix")
    func concurrentReadsSeeAWholePrefix() async {
        let accumulator = SampleAccumulator()
        let value = Float(0.75)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<40 {
                group.addTask { accumulator.append(Array(repeating: value, count: 1024)) }
            }
            for _ in 0..<40 {
                group.addTask {
                    let seen = accumulator.snapshot
                    #expect(seen.allSatisfy { $0 == value })
                    #expect(seen.count % 1024 == 0)
                }
            }
        }

        #expect(accumulator.count == 40 * 1024)
        #expect(accumulator.copiedOnAppend == 0)
    }
}
