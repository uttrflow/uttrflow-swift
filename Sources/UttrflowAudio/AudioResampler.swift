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

        init(slice: AVAudioPCMBuffer, output: AVAudioPCMBuffer) {
            self.slice = slice
            self.output = output
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

        // Above stereo the converter mixes down to silence, so the first channel is taken instead.
        if inputFormat.channelCount > 2 {
            converter.channelMap = [0]
        }

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
        self.scratch = Scratch(slice: slice, output: output)
    }

    /// Converts one buffer. Returns an empty array for an empty input.
    public func resample(_ buffer: AVAudioPCMBuffer) throws(AudioCaptureError) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }

        var converted: [Float] = []
        converted.reserveCapacity(Int((Double(buffer.frameLength) * ratio).rounded(.up)) + 1)

        var offset: AVAudioFrameCount = 0
        while offset < buffer.frameLength {
            let frames = Swift.min(Self.maxFramesPerConversion, buffer.frameLength - offset)
            converted.append(contentsOf: try convert(buffer, from: offset, frames: frames))
            offset += frames
        }
        return converted
    }

    /// Converts one chunk, reusing this resampler's own buffers when the source is in its own format.
    private func convert(
        _ buffer: AVAudioPCMBuffer, from offset: AVAudioFrameCount, frames: AVAudioFrameCount
    ) throws(AudioCaptureError) -> [Float] {
        // The tap always hands back its own format; this is the path the callback thread actually takes.
        if buffer.format == inputFormat {
            return try converter.withLock { converter throws(AudioCaptureError) -> [Float] in
                guard Self.fill(scratch.slice, from: buffer, offset: offset, frames: frames) else {
                    throw .unsupportedInputFormat
                }
                return try Self.convertWhole(scratch.slice, into: scratch.output, using: converter)
            }
        }
        // Only a buffer in a format this resampler was not built for reaches here, which never happens on the tap.
        guard let slice = Self.slice(buffer, from: offset, frames: frames) else {
            throw .unsupportedInputFormat
        }
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw .unsupportedInputFormat
        }
        return try converter.withLock { converter throws(AudioCaptureError) -> [Float] in
            try Self.convertWhole(slice, into: output, using: converter)
        }
    }

    private static func convertWhole(
        _ input: AVAudioPCMBuffer, into output: AVAudioPCMBuffer, using converter: AVAudioConverter
    ) throws(AudioCaptureError) -> [Float] {
        output.frameLength = 0
        var conversionError: NSError?
        let feed = ConversionInput(input)
        let status = converter.convert(to: output, error: &conversionError, withInputFrom: feed.next)

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            break
        case .error:
            throw .engineFailed(description: conversionError?.localizedDescription ?? "conversion failed")
        @unknown default:
            throw .engineFailed(description: "unrecognised conversion result")
        }

        guard let channel = output.floatChannelData?.pointee else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
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
        return output
    }
}

/// Feeds one buffer to `AVAudioConverter` once; the input block never escapes despite being `@Sendable`.
private final class ConversionInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var consumed = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    /// The converter asks repeatedly; the buffer may only be handed over once.
    func next(
        _ packetCount: AVAudioPacketCount,
        _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        guard !consumed else {
            status.pointee = .noDataNow
            return nil
        }
        consumed = true
        status.pointee = .haveData
        return buffer
    }
}
