// Tests the bounded handoff that carries samples off the microphone tap's thread.
import AVFoundation
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import UttrflowAudio

@Suite("TapHandoff")
struct TapHandoffTests {
    /// Collects deliveries on the consumer thread and lets a test wait for a count of them.
    private final class Received: Sendable {
        private let blocks = Mutex<[[Float]]>([])
        private let arrived = DispatchSemaphore(value: 0)

        func take(_ block: [Float]) {
            blocks.withLock { $0.append(block) }
            arrived.signal()
        }

        func wait(for count: Int) -> [[Float]] {
            for _ in 0..<count { _ = arrived.wait(timeout: .now() + 5) }
            return blocks.withLock { $0 }
        }
    }

    @Test("delivers every block whole and in the order it was pushed, across the wrap")
    func ordered() {
        let received = Received()
        let handoff = TapHandoff(capacity: 100) { received.take($0) }
        var expected: [[Float]] = []
        for index in 0..<40 {
            let block = (0..<(index % 7 + 1)).map { Float(index * 10 + $0) }
            expected.append(block)
            block.withUnsafeBufferPointer { _ = handoff.push($0) }
            // Paced so a 100-slot ring wraps many times without filling.
            _ = received.wait(for: 1)
        }
        handoff.finish()
        #expect(received.wait(for: 0) == expected)
        #expect(handoff.droppedSamples == 0)
    }

    @Test("joins the parts of one callback into one block")
    func partsJoin() {
        let received = Received()
        let handoff = TapHandoff { received.take($0) }
        let first: [Float] = [1, 2, 3]
        let second: [Float] = [4, 5]
        handoff.push { part in
            first.withUnsafeBufferPointer(part)
            second.withUnsafeBufferPointer(part)
        }
        handoff.finish()
        #expect(received.wait(for: 1) == [[1, 2, 3, 4, 5]])
    }

    @Test("drops a block that does not fit, counts it, and keeps the blocks either side")
    func overflowIsBounded() {
        let gate = DispatchSemaphore(value: 0)
        let received = Received()
        // The consumer is held on its first block, so the ring fills behind it.
        let handoff = TapHandoff(capacity: 10) { block in
            if block == [0] { gate.wait() }
            received.take(block)
        }
        [Float(0)].withUnsafeBufferPointer { _ = handoff.push($0) }
        Thread.sleep(forTimeInterval: 0.05)
        let six: [Float] = [1, 1, 1, 1, 1, 1]
        let accepted = six.withUnsafeBufferPointer { handoff.push($0) }
        let refused = six.withUnsafeBufferPointer { handoff.push($0) }
        gate.signal()
        handoff.finish()
        #expect(accepted)
        #expect(!refused)
        #expect(handoff.droppedSamples == 6)
        #expect(received.wait(for: 2) == [[0], six])
    }

    @Test("carries one callback's converted chunks as the one block resampling it whole gives")
    func tapPathMatchesResample() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 2))
        let direct = try #require(AudioResampler(inputFormat: format))
        let tapped = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.tone(frequency: 440, frames: 4096, format: format))
        let received = Received()
        let handoff = TapHandoff { received.take($0) }
        var expected: [[Float]] = []
        for _ in 0..<3 {
            expected.append(try direct.resample(buffer))
            handoff.push { part in try? tapped.resample(buffer, into: part) }
        }
        handoff.finish()
        #expect(received.wait(for: 3) == expected)
    }
}
