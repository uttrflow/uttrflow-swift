// Tests the streaming WAV writer.
import Foundation
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

@Suite("RecordingWriter")
struct RecordingWriterTests {
    private struct Sandbox: ~Copyable {
        let directory: URL
        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-writer-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func file(_ name: String) -> URL { directory.appending(path: name) }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    /// The streamed file and the one-shot encoder describe the same audio, so they must agree to the byte.
    @Test("writes the same bytes the encoder would, block by block")
    func matchesTheEncoder() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("take.wav")
        let samples: [Float] = (0..<5_000).map { sin(Float($0) * 0.03) * 0.4 }
        let writer = try RecordingWriter(url: url)

        writer.append(Array(samples[0..<2_000]))
        writer.append(Array(samples[2_000..<4_096]))
        writer.append([])
        writer.append(Array(samples[4_096...]))
        let recording = writer.finish()

        #expect(try Data(contentsOf: url) == WAVEncoder.encode(.canonical(samples)))
        #expect(recording.duration == .seconds(5_000.0 / 16_000.0))
        #expect(recording.id == writer.id)
    }

    @Test("a finished file reads back through the audio reader")
    func readsBack() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("take.wav")
        let writer = try RecordingWriter(url: url)
        writer.append(Array(repeating: 0.25, count: 1_600))
        _ = writer.finish()

        let read = try AudioFileReader.read(contentsOf: url)
        #expect(read.samples.count == 1_600)
        #expect(abs((read.samples.first ?? 0) - 0.25) < 0.001)
    }

    @Test("finishing twice does not write twice")
    func finishIsIdempotent() throws {
        let sandbox = Sandbox()
        let writer = try RecordingWriter(url: sandbox.file("take.wav"))
        writer.append([0.1, 0.2])
        let first = writer.finish()
        writer.append([0.3])
        let second = writer.finish()
        #expect(first == second)
    }

    @Test("abandoning deletes the file")
    func abandonDeletes() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("take.wav")
        let writer = try RecordingWriter(url: url)
        writer.append([0.1])
        writer.abandon()
        writer.abandon()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("refuses a path that cannot be created")
    func refusesAnImpossiblePath() {
        let sandbox = Sandbox()
        #expect(throws: AudioCaptureError.self) {
            try RecordingWriter(url: sandbox.file("missing/take.wav"))
        }
    }

    /// A crash mid-recording leaves the header claiming no frames, which no reader will open.
    @Test("repairs a header the writer never got to finish")
    func repairsAnUnfinishedHeader() throws {
        let sandbox = Sandbox()
        let url = sandbox.file("crashed.wav")
        var data = WAVEncoder.header(frames: 0, sampleRate: AudioSamples.canonicalSampleRate)
        data.append(WAVEncoder.pcm(Array(repeating: 0.5, count: 800)))
        try data.write(to: url)

        RecordingWriter.repair(url)

        #expect(try Data(contentsOf: url) == WAVEncoder.encode(.canonical(Array(repeating: 0.5, count: 800))))
        #expect(try AudioFileReader.read(contentsOf: url).samples.count == 800)
    }

    @Test("leaves a finished file and an empty one alone")
    func repairLeavesGoodFilesAlone() throws {
        let sandbox = Sandbox()
        let finished = sandbox.file("finished.wav")
        let expected = WAVEncoder.encode(.canonical([0.1, 0.2, 0.3]))
        try expected.write(to: finished)
        let empty = sandbox.file("empty.wav")
        try WAVEncoder.header(frames: 0, sampleRate: AudioSamples.canonicalSampleRate).write(to: empty)

        RecordingWriter.repair(finished)
        RecordingWriter.repair(empty)
        RecordingWriter.repair(sandbox.file("absent.wav"))

        #expect(try Data(contentsOf: finished) == expected)
        #expect(try Data(contentsOf: empty).count == WAVEncoder.headerSize)
    }
}
