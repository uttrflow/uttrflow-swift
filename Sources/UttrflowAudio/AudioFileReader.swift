public import Foundation
public import UttrflowCore
private import AVFoundation

/// Reads an audio file into canonical samples.
///
/// Needed to transcribe something already recorded, and to run the evaluation corpus.
/// Reuses ``AudioResampler``, so a file in any format arrives in exactly the same
/// shape as live microphone audio — the pipeline cannot tell them apart.
public enum AudioFileReader {
    public static func read(contentsOf url: URL) throws(AudioCaptureError) -> AudioSamples {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw .engineFailed(description: error.localizedDescription)
        }

        let format = file.processingFormat
        guard let resampler = AudioResampler(inputFormat: format) else {
            throw .unsupportedInputFormat
        }
        guard file.length > 0 else { return .empty }

        // Read in windows rather than one allocation, so a long recording does not
        // need to fit in memory twice.
        let windowFrames: AVAudioFrameCount = 16_384
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))

        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else {
                throw .unsupportedInputFormat
            }
            do {
                try file.read(into: buffer, frameCount: windowFrames)
            } catch {
                throw .engineFailed(description: error.localizedDescription)
            }
            guard buffer.frameLength > 0 else { break }
            samples.append(contentsOf: try resampler.resample(buffer))
        }

        return .canonical(samples)
    }
}
