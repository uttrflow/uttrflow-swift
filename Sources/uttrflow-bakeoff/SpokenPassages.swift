import Foundation
import UttrflowAudio
import UttrflowCore
import UttrflowEval

/// Turns the profile's passages into audio, with the system speech synthesiser.
///
/// Synthesised rather than recorded, and cached rather than regenerated, for the same
/// reason: a profile has to compare two machines or two commits, and a person reading a
/// paragraph twice does not produce the same seconds of speech either time. The operator
/// is the only one who can record a microphone, and this measurement must not wait on
/// them.
struct SpokenPassages {
    struct Spoken {
        let passage: ProfilePassage
        let samples: AudioSamples
    }

    enum Failure: Error, CustomStringConvertible {
        case synthesisFailed(String)
        case audioUnreadable(String)

        var description: String {
            switch self {
            case .synthesisFailed(let detail): "could not synthesise speech: \(detail)"
            case .audioUnreadable(let detail): "could not read synthesised audio: \(detail)"
            }
        }
    }

    let directory: URL
    let voice: String

    /// Synthesises anything missing or out of date, then reads it all in.
    ///
    /// A passage whose text or voice has changed is re-spoken: a cache keyed only on the
    /// file name would go on reporting yesterday's audio under today's passage, which is
    /// the quiet kind of wrong a performance document never recovers from.
    func prepare(_ passages: [ProfilePassage]) throws(Failure) -> [Spoken] {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        } catch {
            throw .synthesisFailed(error.localizedDescription)
        }

        var spoken: [Spoken] = []
        for passage in passages {
            let audio = directory.appending(path: "\(passage.id).wav")
            let stamp = directory.appending(path: "\(passage.id).spoken")
            let wanted = "\(voice)\n\(passage.text)"

            if (try? String(contentsOf: stamp, encoding: .utf8)) != wanted
                || !FileManager.default.fileExists(atPath: audio.path)
            {
                try synthesise(passage.text, to: audio)
                try? wanted.write(to: stamp, atomically: true, encoding: .utf8)
            }

            do {
                spoken.append(Spoken(passage: passage, samples: try AudioFileReader.read(contentsOf: audio)))
            } catch {
                throw .audioUnreadable("\(passage.id): \(error)")
            }
        }
        return spoken
    }

    /// 16 kHz mono, which is what the recogniser wants and what the microphone path
    /// resamples to, so nothing is resampled twice.
    private func synthesise(_ text: String, to destination: URL) throws(Failure) {
        let format = ["--data-format=LEI16@16000", "--file-format=WAVE", "-o", destination.path]
        // A named voice may simply not be installed on this Mac. Falling back to the
        // system default keeps the profile runnable, and the report says which voice
        // spoke because the seconds of audio depend on it.
        if run(["-v", voice] + format + [text]) { return }
        guard run(format + [text]) else {
            throw .synthesisFailed("`say` failed for \(destination.lastPathComponent)")
        }
    }

    private func run(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
