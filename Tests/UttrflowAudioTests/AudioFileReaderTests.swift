import Foundation
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

@Suite("AudioFileReader")
struct AudioFileReaderTests {
    private struct Sandbox: ~Copyable {
        let directory: URL
        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-audio-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func file(_ name: String) -> URL { directory.appending(path: name) }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    /// The encoder and the reader are the two halves of the corpus, so they are tested against each other.
    @Test("reads back what the encoder wrote")
    func roundTrip() throws {
        let sandbox = Sandbox()
        let samples: [Float] = (0..<8_000).map { sin(Float($0) * 0.05) * 0.5 }
        let url = sandbox.file("tone.wav")
        try WAVEncoder.encode(.canonical(samples)).write(to: url)

        let read = try AudioFileReader.read(contentsOf: url)

        #expect(read.sampleRate == AudioSamples.canonicalSampleRate)
        #expect(read.samples.count == samples.count)
        // 16-bit quantisation costs about 1/32768 per sample.
        let worst = zip(read.samples, samples).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 0.001, "largest deviation \(worst)")
    }

    @Test("reads a file recorded at another rate as canonical samples")
    func resamplesOnRead() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("48k.wav")
        let at48k = try #require(
            AudioSamples(samples: Array(repeating: 0.25, count: 48_000), sampleRate: 48_000)
        )
        try WAVEncoder.encode(at48k).write(to: url)

        let read = try AudioFileReader.read(contentsOf: url)

        #expect(read.sampleRate == AudioSamples.canonicalSampleRate)
        #expect(abs(read.samples.count - 16_000) < 400, "got \(read.samples.count)")
    }

    @Test("reads a recording longer than one internal window")
    func readsAcrossWindows() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("long.wav")
        try WAVEncoder.encode(.canonical(Array(repeating: 0.1, count: 100_000))).write(to: url)

        #expect(try AudioFileReader.read(contentsOf: url).samples.count == 100_000)
    }

    @Test("reads an empty recording as empty rather than failing")
    func emptyFile() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("empty.wav")
        try WAVEncoder.encode(.canonical([])).write(to: url)

        #expect(try AudioFileReader.read(contentsOf: url).isEmpty)
    }

    @Test("reports a readable failure for a file that is not audio")
    func notAnAudioFile() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("notes.txt")
        try Data("this is not audio".utf8).write(to: url)

        #expect(throws: AudioCaptureError.self) { try AudioFileReader.read(contentsOf: url) }
    }

    @Test("reports a readable failure for a file that is not there")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/uttrflow/missing.wav")
        #expect(throws: AudioCaptureError.self) { try AudioFileReader.read(contentsOf: url) }
    }
}
