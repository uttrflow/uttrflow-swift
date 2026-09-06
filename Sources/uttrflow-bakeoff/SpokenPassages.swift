import Foundation
import UttrflowAudio
import UttrflowCore
import UttrflowEval

/// Turns the profile's passages into repeatable audio. See `Docs/bakeoff-method.md`.
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

    /// Re-speaks any passage whose text or voice has changed, then reads it all in.
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

    /// 16 kHz mono, which is what the recogniser wants, so nothing is resampled twice.
    private func synthesise(_ text: String, to destination: URL) throws(Failure) {
        let format = ["--data-format=LEI16@16000", "--file-format=WAVE", "-o", destination.path]
        // A named voice may not be installed, and the report names whichever one spoke.
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
