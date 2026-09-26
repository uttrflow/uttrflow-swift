// Builds the buffers the system recogniser reads from canonical mono 16 kHz samples.
internal import AVFoundation
private import UttrflowCore

/// Wraps canonical samples in whatever format the analyser asks for, converting when it is not 16 kHz mono.
enum AnalyserInput {
    /// The format canonical samples arrive in.
    static let canonicalFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioSamples.canonicalSampleRate),
        channels: 1, interleaved: false)

    /// The most input frames handed to the converter at once; more is truncated. See Docs/audio-capture.md.
    private static let maxFramesPerConversion = 2048

    /// A buffer in `format` holding `samples`, or `nil` when the format cannot be built or converted to.
    static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if format.sampleRate == Double(AudioSamples.canonicalSampleRate), format.channelCount == 1 {
            return copied(samples, format: format)
        }
        return converted(samples, to: format)
    }

    /// Writes samples straight into a mono 16 kHz buffer of 16-bit or float samples.
    private static func copied(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let int16 = buffer.int16ChannelData {
            for (index, sample) in samples.enumerated() {
                int16[0][index] = Int16(clampingAudioSample: sample)
            }
            return buffer
        }
        if let float = buffer.floatChannelData {
            for (index, sample) in samples.enumerated() { float[0][index] = sample }
            return buffer
        }
        return nil
    }

    /// Resamples and remixes through `AVAudioConverter`, fed a slice at a time and flushed at the end.
    private static func converted(_ samples: [Float], to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let canonicalFormat, let converter = AVAudioConverter(from: canonicalFormat, to: format)
        else { return nil }
        // Mono fed to every output channel, so no channel the analyser reads is silent.
        converter.channelMap = Array(repeating: 0, count: Int(format.channelCount))

        let ratio = format.sampleRate / canonicalFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var slices: [AVAudioPCMBuffer] = []
        for start in stride(from: 0, to: samples.count, by: maxFramesPerConversion) {
            let end = min(start + maxFramesPerConversion, samples.count)
            guard let slice = copied(Array(samples[start..<end]), format: canonicalFormat) else { return nil }
            slices.append(slice)
        }
        let feed = SliceFeed(slices)
        var error: NSError?
        guard converter.convert(to: output, error: &error, withInputFrom: feed.next) != .error else {
            return nil
        }
        return output
    }
}

/// Hands the converter each slice once, then the end of the stream; the block never escapes.
private final class SliceFeed: @unchecked Sendable {
    private var slices: ArraySlice<AVAudioPCMBuffer>

    init(_ slices: [AVAudioPCMBuffer]) { self.slices = slices[...] }

    func next(
        _: AVAudioPacketCount, _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        guard let slice = slices.popFirst() else {
            status.pointee = .endOfStream
            return nil
        }
        status.pointee = .haveData
        return slice
    }
}
