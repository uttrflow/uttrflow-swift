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

    // AVAudioConverter is stateful and not thread-safe; the lock makes that safe rather than lucky.
    private let converter: Mutex<AVAudioConverter>
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    /// Creates a resampler for one input format, or `nil` when the system cannot convert it.
    public init?(inputFormat: AVAudioFormat) {
        guard let outputFormat = Self.canonicalFormat,
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return nil }

        // Above stereo the converter mixes down to silence, so the first channel is taken instead.
        if inputFormat.channelCount > 2 {
            converter.channelMap = [0]
        }

        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = Mutex(converter)
    }

    /// The most input frames fed to the converter at once; more is truncated. See Docs/audio-capture.md.
    private static let maxFramesPerConversion: AVAudioFrameCount = 2048

    /// Converts one buffer. Returns an empty array for an empty input.
    public func resample(_ buffer: AVAudioPCMBuffer) throws(AudioCaptureError) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        var converted: [Float] = []
        converted.reserveCapacity(Int((Double(buffer.frameLength) * ratio).rounded(.up)) + 1)

        var offset: AVAudioFrameCount = 0
        while offset < buffer.frameLength {
            let frames = Swift.min(Self.maxFramesPerConversion, buffer.frameLength - offset)
            guard let slice = Self.slice(buffer, from: offset, frames: frames) else {
                throw .unsupportedInputFormat
            }
            converted.append(contentsOf: try convertWhole(slice, ratio: ratio))
            offset += frames
        }
        return converted
    }

    private func convertWhole(
        _ buffer: AVAudioPCMBuffer, ratio: Double
    ) throws(AudioCaptureError) -> [Float] {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw .unsupportedInputFormat
        }

        var conversionError: NSError?
        let input = ConversionInput(buffer)
        let status = converter.withLock { converter in
            converter.convert(to: output, error: &conversionError, withInputFrom: input.next)
        }

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
