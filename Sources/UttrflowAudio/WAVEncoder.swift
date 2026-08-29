public import Foundation
public import UttrflowCore

/// Writes canonical samples out as a 16-bit PCM WAV file.
///
/// Needed in two places — letting a developer hear what was captured, and building the
/// evaluation corpus — so it lives here rather than in whichever one needed it first.
///
/// Deliberately not reachable from the app. There was a third reason once, keeping the
/// user's recordings for a retention window, and it was dropped: Uttrflow never writes
/// audio to disk, and the privacy promise now says so. Anything that links this type
/// into the shipping app is a change of that promise, not a refactor.
public enum WAVEncoder {
    private static let bitsPerSample = 16
    private static let channelCount = 1
    private static let pcmFormatTag: UInt16 = 1

    /// Encodes `audio` as a complete WAV file.
    public static func encode(_ audio: AudioSamples) -> Data {
        let bytesPerFrame = channelCount * bitsPerSample / 8
        let payloadSize = audio.samples.count * bytesPerFrame

        var data = Data(capacity: 44 + payloadSize)
        data.append(ascii: "RIFF")
        data.append(littleEndian: UInt32(36 + payloadSize))
        data.append(ascii: "WAVE")

        data.append(ascii: "fmt ")
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: pcmFormatTag)
        data.append(littleEndian: UInt16(channelCount))
        data.append(littleEndian: UInt32(audio.sampleRate))
        data.append(littleEndian: UInt32(audio.sampleRate * bytesPerFrame))
        data.append(littleEndian: UInt16(bytesPerFrame))
        data.append(littleEndian: UInt16(bitsPerSample))

        data.append(ascii: "data")
        data.append(littleEndian: UInt32(payloadSize))
        for sample in audio.samples {
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
