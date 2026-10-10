// Converts any microphone format into canonical mono 16 kHz samples.
public import AVFoundation
public import UttrflowCore
private import Synchronization

/// Converts microphone buffers of any format into canonical mono 16 kHz samples. See Docs/audio-capture.md.
public final class AudioResampler: Sendable {
    /// The format every consumer in the product expects.
    public static let canonicalFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(AudioSamples.canonicalSampleRate),
        channels: 1,
        interleaved: false
    )

    /// The reused buffers behind the lock below, a class so the lock can guard them without owning a struct of them.
    private final class Scratch: @unchecked Sendable {
        /// Reused input slice, sized for the largest chunk this resampler ever takes. See Docs/audio-capture.md.
        let slice: AVAudioPCMBuffer
        /// Reused conversion output, sized once for the largest chunk this resampler ever produces.
        let output: AVAudioPCMBuffer
        /// Reused per-channel energy totals for choosing the active microphone input.
        var channelEnergy: [Double]
        var selectedChannel = 0
        /// Reused converter input, so a chunk does not allocate the object that hands its slice over.
        let feed = ConversionInput()

        init(slice: AVAudioPCMBuffer, output: AVAudioPCMBuffer, channelCount: AVAudioChannelCount) {
            self.slice = slice
            self.output = output
            self.channelEnergy = Array(repeating: 0, count: Int(channelCount))
        }
    }

    // AVAudioConverter is stateful and not thread-safe; the lock makes that safe rather than lucky.
    private let converter: Mutex<AVAudioConverter>
    /// Only ever touched while `converter`'s lock is held, so reuse across calls never races the tap.
    private let scratch: Scratch
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    /// The most input frames fed to the converter at once; more is truncated. See Docs/audio-capture.md.
    private static let maxFramesPerConversion: AVAudioFrameCount = 2048

    /// Creates a resampler for one input format, or `nil` when the system cannot convert it.
    public init?(inputFormat: AVAudioFormat) {
        guard let outputFormat = Self.canonicalFormat,
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return nil }
        if inputFormat.channelCount > 1 { converter.channelMap = [0] }
        // The default leaks a 9 kHz tone at about -19 dB at 48 kHz; see Docs/audio-capture.md.
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity =
            AVAudioFrameCount((Double(Self.maxFramesPerConversion) * ratio).rounded(.up)) + 64
        guard
            let slice = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.maxFramesPerConversion),
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity)
        else { return nil }

        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.ratio = ratio
        self.converter = Mutex(converter)
        self.scratch = Scratch(
            slice: slice, output: output, channelCount: inputFormat.channelCount)
    }

    /// Converts one buffer. Returns an empty array for an empty input.
    public func resample(_ buffer: AVAudioPCMBuffer) throws(AudioCaptureError) -> [Float] {
        var converted: [Float] = []
        converted.reserveCapacity(Int((Double(buffer.frameLength) * ratio).rounded(.up)) + 1)
        try resample(buffer) { converted.append(contentsOf: $0) }
        return converted
    }

    /// Converts one buffer chunk by chunk, lending each chunk out of reused storage, so the tap allocates no array.
    public func resample(
        _ buffer: AVAudioPCMBuffer, into consume: (UnsafeBufferPointer<Float>) -> Void
    ) throws(AudioCaptureError) {
        var offset: AVAudioFrameCount = 0
        while offset < buffer.frameLength {
            let frames = Swift.min(Self.maxFramesPerConversion, buffer.frameLength - offset)
            try convert(buffer, from: offset, frames: frames, into: consume)
            offset += frames
        }
    }

    /// Converts one chunk, reusing this resampler's own buffers when the source is in its own format.
    private func convert(
        _ buffer: AVAudioPCMBuffer, from offset: AVAudioFrameCount, frames: AVAudioFrameCount,
        into consume: (UnsafeBufferPointer<Float>) -> Void
    ) throws(AudioCaptureError) {
        // The tap always hands back its own format; this is the path the callback thread actually takes.
        if buffer.format == inputFormat {
            try converter.withLock { converter throws(AudioCaptureError) in
                guard Self.fill(scratch.slice, from: buffer, offset: offset, frames: frames) else {
                    throw .unsupportedInputFormat
                }
                if inputFormat.channelCount > 1 {
                    let channel = Self.strongestChannel(
                        in: scratch.slice, energy: &scratch.channelEnergy)
                    if channel != scratch.selectedChannel {
                        converter.channelMap = [NSNumber(value: channel)]
                        scratch.selectedChannel = channel
                    }
                }
                consume(
                    try Self.convertWhole(
                        scratch.slice, into: scratch.output, using: converter, feeding: scratch.feed))
            }
            return
        }
        // Only a buffer in a format this resampler was not built for reaches here, which never happens on the tap.
        guard let slice = Self.slice(buffer, from: offset, frames: frames) else {
            throw .unsupportedInputFormat
        }
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw .unsupportedInputFormat
        }
        try converter.withLock { converter throws(AudioCaptureError) in
            consume(
                try Self.convertWhole(slice, into: output, using: converter, feeding: ConversionInput()))
        }
    }

    /// Converts `input` into `output` and lends out its samples, valid only until `output` is next written.
    private static func convertWhole(
        _ input: AVAudioPCMBuffer, into output: AVAudioPCMBuffer, using converter: AVAudioConverter,
        feeding feed: ConversionInput
    ) throws(AudioCaptureError) -> UnsafeBufferPointer<Float> {
        output.frameLength = 0
        var conversionError: NSError?
        feed.load(input)
        let status = converter.convert(to: output, error: &conversionError, withInputFrom: feed.next)

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            break
        case .error:
            throw .engineFailed(description: conversionError?.localizedDescription ?? "conversion failed")
        @unknown default:
            throw .engineFailed(description: "unrecognised conversion result")
        }

        guard let channel = output.floatChannelData?.pointee else {
            return UnsafeBufferPointer(start: nil, count: 0)
        }
        // Filtering can overshoot, so downstream consumers receive bounded, finite samples.
        for index in 0..<Int(output.frameLength) {
            let sample = channel[index]
            channel[index] = sample.isFinite ? min(max(sample, -1), 1) : 0
        }
        return UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
    }

    /// Selects the channel with the most input energy so inactive channels and phase cancellation do not erase speech.
    private static func strongestChannel(in input: AVAudioPCMBuffer, energy: inout [Double]) -> Int {
        let channelCount = Int(input.format.channelCount)
        let frames = Int(input.frameLength)
        guard channelCount > 1, frames > 0, energy.count == channelCount else { return 0 }
        for channel in energy.indices { energy[channel] = 0 }

        switch input.format.commonFormat {
        case .pcmFormatFloat32:
            accumulateEnergy(in: input, into: &energy) { (sample: Float) in Double(sample) }
        case .pcmFormatFloat64:
            accumulateEnergy(in: input, into: &energy) { (sample: Double) in sample }
        case .pcmFormatInt16:
            accumulateEnergy(in: input, into: &energy) { (sample: Int16) in Double(sample) }
        case .pcmFormatInt32:
            accumulateEnergy(in: input, into: &energy) { (sample: Int32) in Double(sample) }
        default:
            return 0
        }

        var strongest = 0
        for channel in 1..<channelCount where energy[channel] > energy[strongest] {
            strongest = channel
        }
        return strongest
    }

    private static func accumulateEnergy<Sample>(
        in input: AVAudioPCMBuffer, into energy: inout [Double], convert: (Sample) -> Double
    ) {
        let channelCount = Int(input.format.channelCount)
        let frames = Int(input.frameLength)
        let buffers = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        if input.format.isInterleaved {
            guard buffers.count == 1, let memory = buffers[0].mData else { return }
            let samples = memory.assumingMemoryBound(to: Sample.self)
            for frame in 0..<frames {
                for channel in 0..<channelCount {
                    let sample = convert(samples[frame * channelCount + channel])
                    energy[channel] += sample * sample
                }
            }
        } else {
            guard buffers.count == channelCount else { return }
            for channel in 0..<channelCount {
                guard let memory = buffers[channel].mData else { return }
                let samples = memory.assumingMemoryBound(to: Sample.self)
                for frame in 0..<frames {
                    let sample = convert(samples[frame])
                    energy[channel] += sample * sample
                }
            }
        }
    }

    /// Copies `frames` from `offset` of `source` into `destination` in place, off the raw buffer list so any layout is right.
    private static func fill(
        _ destination: AVAudioPCMBuffer, from source: AVAudioPCMBuffer,
        offset: AVAudioFrameCount, frames: AVAudioFrameCount
    ) -> Bool {
        destination.frameLength = frames
        let from = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let into = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard from.count == into.count else { return false }

        for index in 0..<from.count {
            guard let src = from[index].mData, let dst = into[index].mData else { return false }
            let bytesPerFrame = Int(from[index].mDataByteSize) / Int(source.frameLength)
            dst.copyMemory(
                from: src.advanced(by: Int(offset) * bytesPerFrame),
                byteCount: Int(frames) * bytesPerFrame
            )
        }
        sanitizeNonFiniteSamples(in: destination)
        return true
    }

    /// Copies `frames` from `offset` into a new buffer, off the raw buffer list so any layout is right.
    private static func slice(
        _ buffer: AVAudioPCMBuffer, from offset: AVAudioFrameCount, frames: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard let output = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) else {
            return nil
        }
        output.frameLength = frames

        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }

        for index in 0..<source.count {
            guard let from = source[index].mData, let into = destination[index].mData else { return nil }
            let bytesPerFrame = Int(source[index].mDataByteSize) / Int(buffer.frameLength)
            into.copyMemory(
                from: from.advanced(by: Int(offset) * bytesPerFrame),
                byteCount: Int(frames) * bytesPerFrame
            )
        }
        sanitizeNonFiniteSamples(in: output)
        return output
    }

    private static func sanitizeNonFiniteSamples(in buffer: AVAudioPCMBuffer) {
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            sanitizeNonFiniteSamples(in: buffer, as: Float.self)
        case .pcmFormatFloat64:
            sanitizeNonFiniteSamples(in: buffer, as: Double.self)
        default:
            break
        }
    }

    private static func sanitizeNonFiniteSamples<Sample: BinaryFloatingPoint>(
        in buffer: AVAudioPCMBuffer, as sampleType: Sample.Type
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let channelsPerBuffer = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        let expectedCount = Int(buffer.frameLength) * channelsPerBuffer

        for audioBuffer in buffers {
            guard let data = audioBuffer.mData else { continue }
            let availableCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Sample>.size
            let samples = UnsafeMutableBufferPointer(
                start: data.assumingMemoryBound(to: Sample.self),
                count: min(expectedCount, availableCount)
            )
            for index in samples.indices where !samples[index].isFinite {
                samples[index] = 0
            }
        }
    }
}

/// Feeds one buffer to `AVAudioConverter` once; the input block never escapes despite being `@Sendable`.
private final class ConversionInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    private var consumed = true

    /// Arms this input with the next buffer to hand over once.
    func load(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
        consumed = false
    }

    /// The converter asks repeatedly; the buffer may only be handed over once.
    func next(
        _ packetCount: AVAudioPacketCount,
        _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        guard !consumed, let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        consumed = true
        status.pointee = .haveData
        return buffer
    }
}
