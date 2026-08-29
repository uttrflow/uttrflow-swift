public import AVFoundation
public import UttrflowCore
private import Synchronization

/// Converts microphone buffers of any format into canonical mono 16 kHz samples.
///
/// Microphones hand back whatever they like — 44.1 or 48 kHz, one channel or several,
/// interleaved or not. Normalising once, here, is why nothing downstream has to care.
public final class AudioResampler: Sendable {
    /// The format every consumer in the product expects.
    public static let canonicalFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(AudioSamples.canonicalSampleRate),
        channels: 1,
        interleaved: false
    )

    // AVAudioConverter is stateful and not thread-safe. It is only ever touched from
    // the capture thread, but the lock makes that safe rather than merely true today.
    private let converter: Mutex<AVAudioConverter>
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    /// Creates a resampler for one input format.
    ///
    /// - Returns: `nil` when the system cannot convert between the two formats, which
    ///   the caller should surface as ``AudioCaptureError/unsupportedInputFormat``.
    public init?(inputFormat: AVAudioFormat) {
        guard let outputFormat = Self.canonicalFormat,
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return nil }

        // Above stereo, the converter has no spatial mapping to mix down with and
        // silently produces silence — a dead microphone on a multi-input audio
        // interface. Taking the first channel is predictable and audible; mono and
        // stereo keep the default, which averages properly.
        if inputFormat.channelCount > 2 {
            converter.channelMap = [0]
        }

        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = Mutex(converter)
    }

    /// The most input frames handed to the converter at once.
    ///
    /// `AVAudioConverter` consumes roughly 4000 frames per supply and then reports
    /// `inputRanDry` rather than asking again, so a single large buffer is silently
    /// truncated — measured at 51% of the expected output when upsampling 8 kHz.
    /// Feeding it in slices recovers 99.8%. Calling convert repeatedly does not help;
    /// only re-supplying does.
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

    /// Copies `frames` starting at `offset` into a new buffer of the same format.
    ///
    /// Works off the raw buffer list rather than `floatChannelData`, so it is correct
    /// for interleaved and deinterleaved layouts alike: in both, a buffer's byte size
    /// divided by its frame count is the bytes it holds per frame.
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

/// Feeds one buffer to `AVAudioConverter`, exactly once.
///
/// The converter's input block is declared `@Sendable`, but it is called synchronously
/// on the converting thread before `convert` returns — it never escapes. Stating that
/// here keeps the unchecked conformance in one documented place instead of spreading
/// it across the call site.
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
