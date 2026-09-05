public import Foundation
public import UttrflowCore

/// Writes canonical samples out as a 16-bit PCM WAV file. See `Docs/recordings.md`.
public enum WAVEncoder {
    private static let bitsPerSample = 16
    private static let channelCount = 1
    private static let pcmFormatTag: UInt16 = 1
    /// Bytes one frame of 16-bit mono takes.
    static let bytesPerFrame = channelCount * bitsPerSample / 8
    /// Bytes before the first sample.
    static let headerSize = 44
    /// Where the data chunk's byte count sits in the header.
    static let dataSizeOffset = 40

    /// Encodes `audio` as a complete WAV file.
    public static func encode(_ audio: AudioSamples) -> Data {
        var data = header(frames: audio.samples.count, sampleRate: audio.sampleRate)
        data.append(pcm(audio.samples))
        return data
    }

    /// The 44-byte header declaring `frames` of 16-bit mono at `sampleRate`.
    static func header(frames: Int, sampleRate: Int) -> Data {
        let payloadSize = frames * bytesPerFrame
        var data = Data(capacity: headerSize)
        data.append(ascii: "RIFF")
        data.append(littleEndian: UInt32(36 + payloadSize))
        data.append(ascii: "WAVE")

        data.append(ascii: "fmt ")
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: pcmFormatTag)
        data.append(littleEndian: UInt16(channelCount))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(sampleRate * bytesPerFrame))
        data.append(littleEndian: UInt16(bytesPerFrame))
        data.append(littleEndian: UInt16(bitsPerSample))

        data.append(ascii: "data")
        data.append(littleEndian: UInt32(payloadSize))
        return data
    }

    /// How many frames a file of `bytes` holds after its header.
    static func frames(inFileOf bytes: Int) -> Int {
        max(0, bytes - headerSize) / bytesPerFrame
    }

    /// The samples as little-endian 16-bit integers, clamped to full scale.
    static func pcm(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * bytesPerFrame)
        for sample in samples {
            data.append(littleEndian: Int16(clampingAudioSample: sample))
        }
        return data
    }
}

extension Data {
    fileprivate mutating func append(ascii text: String) {
        append(contentsOf: text.utf8)
    }

    fileprivate mutating func append(littleEndian value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
