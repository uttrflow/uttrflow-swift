import AVFoundation
import Synchronization

@testable import UttrflowAudio
@testable import UttrflowCore

/// A ``MicrophoneSource`` that emits exactly what a test tells it to.
final class FakeMicrophoneSource: MicrophoneSource {
    private struct State {
        var handler: (@Sendable ([Float]) -> Void)?
        var startCount = 0
        var stopCount = 0
        var startError: AudioCaptureError?
    }

    private let state = Mutex(State())

    init(startError: AudioCaptureError? = nil) {
        state.withLock { $0.startError = startError }
    }

    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws(AudioCaptureError) {
        let error = state.withLock { state -> AudioCaptureError? in
            state.startCount += 1
            if state.startError == nil { state.handler = onSamples }
            return state.startError
        }
        if let error { throw error }
    }

    func stop() {
        state.withLock { state in
            state.stopCount += 1
            state.handler = nil
        }
    }

    /// Delivers samples the way a real tap would, from outside the engine's actor.
    func emit(_ samples: [Float]) {
        state.withLock(\.handler)?(samples)
    }

    var isDelivering: Bool { state.withLock { $0.handler != nil } }
    var startCount: Int { state.withLock(\.startCount) }
    var stopCount: Int { state.withLock(\.stopCount) }
}

/// Builds a PCM buffer without touching hardware.
enum SyntheticAudio {
    static func format(
        sampleRate: Double, channels: AVAudioChannelCount, interleaved: Bool = false
    )
        -> AVAudioFormat?
    {
        // The convenience initialiser only knows mono and stereo layouts; anything
        // wider — a 4-input audio interface, say — needs an explicit one.
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

    /// A sine wave, for checking that resampling preserves a signal rather than
    /// merely producing the right number of samples.
    static func tone(
        frequency: Double, frames: AVAudioFrameCount, format: AVAudioFormat, amplitude: Float = 0.5
    ) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frames
        let step = 2 * Double.pi * frequency / format.sampleRate
        for frame in 0..<Int(frames) {
            let value = amplitude * Float(Foundation.sin(step * Double(frame)))
            for channel in 0..<Int(format.channelCount) { channels[channel][frame] = value }
        }
        return buffer
    }
}
