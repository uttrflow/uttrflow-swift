// A fake microphone source and synthetic audio for the audio tests.
import AVFoundation
import Synchronization

@testable import UttrflowAudio
@testable import UttrflowCore

/// A ``MicrophoneSource`` that emits exactly what a test tells it to.
final class FakeMicrophoneSource: MicrophoneSource {
    private struct State {
        var handler: (@Sendable ([Float]) -> Void)?
        var handedOut: [@Sendable ([Float]) -> Void] = []
        var interrupted: (@Sendable (CaptureInterruption) -> Void)?
        var startCount = 0
        var stopCount = 0
        var drainedCount = 0
        var heldAtStop: [Float]?
        var startError: AudioCaptureError?
        var gaps = CaptureGaps.none
        var chosenInputMissing = false
    }

    private let state = Mutex(State())

    init(startError: AudioCaptureError? = nil) {
        state.withLock { $0.startError = startError }
    }

    func start(
        onSamples: @escaping @Sendable ([Float]) -> Void,
        onInterruption: @escaping @Sendable (CaptureInterruption) -> Void
    ) throws(AudioCaptureError) {
        let error = state.withLock { state -> AudioCaptureError? in
            state.startCount += 1
            if state.startError == nil {
                state.handler = onSamples
                state.handedOut.append(onSamples)
                state.interrupted = onInterruption
            }
            return state.startError
        }
        if let error { throw error }
    }

    /// Says the microphone stopped for good, which is what a device that never came back does.
    func die(_ error: AudioCaptureError = .engineFailed(description: "gone")) {
        state.withLock { $0.interrupted }?(.ended(error))
    }

    /// The interruption callback the current recording was started with, so a test can fire it late.
    var interruptionHandler: (@Sendable (CaptureInterruption) -> Void)? {
        state.withLock(\.interrupted)
    }

    /// Says the device went and came back, which leaves a hole in the middle of the recording.
    func skip() {
        state.withLock { $0.interrupted }?(.began)
    }

    /// Hands over one last block while draining, which is what a tap holding a part-filled buffer does.
    func stop(draining: Bool) async {
        if draining, let tail = state.withLock(\.heldAtStop) { emit(tail) }
        state.withLock { state in
            state.stopCount += 1
            state.drainedCount += draining ? 1 : 0
            state.handler = nil
        }
    }

    /// What the hardware is still holding when the key comes up, delivered only to a stop that drains.
    func holdAtStop(_ samples: [Float]) {
        state.withLock { $0.heldAtStop = samples }
    }

    /// Delivers samples the way a real tap would, from outside the engine's actor.
    func emit(_ samples: [Float]) {
        state.withLock(\.handler)?(samples)
    }

    /// Calls the sink a given start handed over, as a render callback already in flight at teardown does.
    func emitLate(_ samples: [Float], toStart index: Int) {
        state.withLock { $0.handedOut[index] }(samples)
    }

    /// Holes the hardware clock would have counted, reported as a real source does after a stop.
    var gaps: CaptureGaps {
        get { state.withLock(\.gaps) }
        set { state.withLock { $0.gaps = newValue } }
    }

    /// Whether the chosen input was missing, reported as a real source does after a stop.
    var chosenInputMissing: Bool {
        get { state.withLock(\.chosenInputMissing) }
        set { state.withLock { $0.chosenInputMissing = newValue } }
    }

    var isDelivering: Bool { state.withLock { $0.handler != nil } }
    var startCount: Int { state.withLock(\.startCount) }
    var stopCount: Int { state.withLock(\.stopCount) }
    var drainedCount: Int { state.withLock(\.drainedCount) }
}

/// Builds a PCM buffer without touching hardware.
enum SyntheticAudio {
    static func format(
        sampleRate: Double, channels: AVAudioChannelCount, interleaved: Bool = false
    )
        -> AVAudioFormat?
    {
        // The convenience initialiser only knows mono and stereo; anything wider needs an explicit layout.
        guard channels > 2 else {
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: interleaved
            )
        }
        guard
            let layout = AVAudioChannelLayout(
                layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels
            )
        else { return nil }
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout)
    }

    /// A buffer whose every sample is `value`.
    static func constant(
        _ value: Float, frames: AVAudioFrameCount, format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frames) { channels[channel][frame] = value }
        }
        return buffer
    }

    /// A sine wave, for checking that resampling preserves a signal and not only the sample count.
    static func tone(
        frequency: Double, frames: AVAudioFrameCount, format: AVAudioFormat, amplitude: Float = 0.5
    ) -> AVAudioPCMBuffer? {
        tone(
            frequency: frequency, frames: frames, format: format,
            channelAmplitudes: Array(repeating: amplitude, count: Int(format.channelCount)))
    }

    /// A sine wave with explicit per-channel amplitudes for channel mapping tests.
    static func tone(
        frequency: Double, frames: AVAudioFrameCount, format: AVAudioFormat,
        channelAmplitudes: [Float]
    ) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let channels = buffer.floatChannelData,
            channelAmplitudes.count == Int(format.channelCount)
        else { return nil }
        buffer.frameLength = frames
        let step = 2 * Double.pi * frequency / format.sampleRate
        for channel in channelAmplitudes.indices {
            for frame in 0..<Int(frames) {
                channels[channel][frame] =
                    channelAmplitudes[channel]
                    * Float(Foundation.sin(step * Double(frame)))
            }
        }
        return buffer
    }
}
