// Tests that the tap checks its buffers against the hardware clock instead of joining across a lost one.
import AVFoundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAudio

@Suite("CaptureTimeline")
struct CaptureTimelineTests {
    @Test("buffers that follow on, or jitter by under half a buffer, are continuous")
    func continuous() {
        var timeline = CaptureTimeline(sampleRate: 48_000)
        #expect(timeline.arrived(at: 0, frames: 4096) == .continuous)
        timeline.delivered(at: 0, frames: 4096)
        #expect(timeline.arrived(at: 4096, frames: 4096) == .continuous)
        #expect(timeline.arrived(at: 4096 + 2048, frames: 4096) == .continuous)
        #expect(timeline.arrived(at: 100, frames: 4096) == .continuous)
        #expect(timeline.arrived(at: nil, frames: 4096) == .continuous)
        #expect(timeline.gaps == 0)
    }

    @Test("a short hole becomes silence of the same length at the canonical rate")
    func shortHoleIsFilled() {
        var timeline = CaptureTimeline(sampleRate: 48_000)
        timeline.delivered(at: 0, frames: 1024)
        // 3072 frames at 48 kHz is 64 ms, 1024 canonical frames.
        #expect(timeline.arrived(at: 1024 + 3072, frames: 1024) == .silence(canonicalFrames: 1024))
        #expect(timeline.gaps == 1)
        #expect(timeline.gapMilliseconds == 64)
    }

    @Test("a hole past the bound breaks the recording, and still counts")
    func longHoleBreaks() {
        var timeline = CaptureTimeline(sampleRate: 48_000)
        timeline.delivered(at: 0, frames: 4096)
        #expect(timeline.arrived(at: 4096 + 4801, frames: 4096) == .broken)
        #expect(timeline.gapFrames == 4801)
    }

    @Test("a lost buffer shows as the hole before the next one")
    func droppedBufferReappearsAsHole() {
        var timeline = CaptureTimeline(sampleRate: 16_000)
        timeline.delivered(at: 0, frames: 1000)
        timeline.dropped()
        #expect(timeline.arrived(at: 2000, frames: 1000) == .silence(canonicalFrames: 1000))
        timeline.dropped(resumingAt: 2000)
        #expect(timeline.arrived(at: 3000, frames: 1000) == .silence(canonicalFrames: 1000))
        #expect(timeline.droppedBuffers == 2)
    }

    @Test("a device that skips buffers yields samples for the time that passed, within one block")
    func skippedBuffersKeepTheClock() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.tone(frequency: 440, frames: 1024, format: format))
        let total = Mutex(0)
        let handoff = TapHandoff { block in total.withLock { $0 += block.count } }
        let clock = TapClock(sampleRate: 48_000)
        var start: Int64 = 0
        for index in 0..<201 {
            // Every fifth buffer never arrives, as when the machine is too busy to call the tap.
            if index % 5 != 4 { clock.deliver(buffer, at: start, through: resampler, into: handoff) }
            start += 1024
        }
        handoff.finish()
        let elapsed = Int(start) / 3
        #expect(abs(total.withLock { $0 } - elapsed) <= 1024 / 3 + 1)
        #expect(clock.timeline.gaps == 40)
        #expect(!clock.takeBreak())
    }

    @Test("a hole past the bound is flagged once for the session to refuse")
    func longSkipIsFlagged() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.tone(frequency: 440, frames: 4096, format: format))
        let handoff = TapHandoff { _ in }
        let clock = TapClock(sampleRate: 48_000)
        clock.deliver(buffer, at: 0, through: resampler, into: handoff)
        clock.deliver(buffer, at: 4096 * 3, through: resampler, into: handoff)
        handoff.finish()
        #expect(clock.takeBreak())
        #expect(!clock.takeBreak())
    }

    @Test("a block the handoff refuses is counted as dropped")
    func refusedBlockIsDropped() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 16_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.tone(frequency: 440, frames: 1024, format: format))
        let handoff = TapHandoff(capacity: 16) { _ in }
        let clock = TapClock(sampleRate: 16_000)
        clock.deliver(buffer, at: 0, through: resampler, into: handoff)
        handoff.finish()
        #expect(clock.timeline.droppedBuffers == 1)
    }
}
