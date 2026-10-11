// Resolves which voice `say` will actually speak with, since `say -v <name>` can exit 0 for a name `say -v ?` never lists.
public import Foundation

/// The voices `say -v <name>` will actually speak with, as `say -v ?` reports them.
public protocol VoiceCatalogue: Sendable {
    func installedVoiceNames() -> Set<String>
}

/// Runs the synthesizer, injectable so a resolved voice can be tested without a real `say`.
public protocol VoiceSynthesizer: Sendable {
    /// Writes `text` as audio at `destination`, in `voice` or the system default when `voice` is `nil`.
    func speak(_ text: String, voice: String?, to destination: URL) -> Bool
}

/// What `--voice <requested>` resolved to, once checked against what is actually installed.
public struct ResolvedVoice: Sendable, Equatable {
    /// The name `--voice` asked for.
    public let requested: String
    /// `requested`, when it is installed; `nil` when the system default spoke instead.
    public let installed: String?

    public init(requested: String, installed: String?) {
        self.requested = requested
        self.installed = installed
    }

    /// The exact voice that produced the audio: `installed`, or a fallback that names what was asked for.
    public var label: String {
        installed ?? "system default (\"\(requested)\" is not installed)"
    }
}

/// Checks `requested` against `catalogue`, so a name `say` accepts without installing it never passes as real.
public func resolveVoice(requested: String, catalogue: any VoiceCatalogue) -> ResolvedVoice {
    ResolvedVoice(
        requested: requested,
        installed: catalogue.installedVoiceNames().contains(requested) ? requested : nil)
}

/// Parses `say -v ?`, the same listing `say -v <name>` is silently willing to ignore.
public struct SayVoiceCatalogue: VoiceCatalogue {
    public init() {}

    public func installedVoiceNames() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "?"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return []
        }
        // Each line is "Name   xx_XX    # sample"; the locale code anchors the split since a name may itself hold spaces.
        return Set(
            text.split(separator: "\n").compactMap { line -> String? in
                guard
                    let localeRange = line.range(
                        of: #"  +[a-z]{2}(-[A-Za-z]+)?_[A-Z]{2}\b"#, options: .regularExpression)
                else { return nil }
                let name = line[..<localeRange.lowerBound].trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            })
    }
}

/// Invokes `/usr/bin/say`, writing 16 kHz mono WAV — what the recogniser wants, so nothing resamples twice.
public struct SaySynthesizer: VoiceSynthesizer {
    /// Words per minute, passed as `say -r`; `nil` keeps the voice's own rate.
    package let rate: Int?

    public init() { rate = nil }

    package init(rate: Int?) { self.rate = rate }

    public func speak(_ text: String, voice: String?, to destination: URL) -> Bool {
        var arguments = voice.map { ["-v", $0] } ?? []
        arguments += rate.map { ["-r", String($0)] } ?? []
        arguments += ["--data-format=LEI16@16000", "--file-format=WAVE", "-o", destination.path, text]
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
