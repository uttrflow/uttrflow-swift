// System voices reading an invented text set, as one more source of `harvest-confusions` manifest lines.
private import Foundation

/// Plans and writes the clips a set of system voices and rates read, as manifest entries the one harvest decodes.
package enum SyntheticHarvestSource {
    /// A system voice and the class its rows are counted under, written `Name:class` on the command line.
    package struct Voice: Sendable, Equatable {
        package let name: String
        package let voiceClass: String

        package init(name: String, voiceClass: String) {
            self.name = name
            self.voiceClass = voiceClass
        }

        /// Reads `Samantha:en_US`; `nil` when either side is empty or the separator is missing.
        package init?(argument: String) {
            let parts = argument.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            self.init(name: parts[0], voiceClass: parts[1])
        }
    }

    /// One clip to synthesise: what is read, by which voice, at what rate, and the file it is written to.
    package struct Take: Sendable, Equatable {
        package let text: String
        package let voice: Voice
        package let rate: Int
        package let file: String

        /// The manifest line for this take; the voice and rate stand in for a speaker, the class for a group.
        package var entry: AccentSlice.Entry {
            AccentSlice.Entry(
                audio: file, reference: text, group: voice.voiceClass, speaker: "\(voice.name)@\(rate)")
        }
    }

    /// Every sentence read by every voice at every rate, in a fixed order with file names that depend only on the inputs.
    package static func takes(sentences: [String], voices: [Voice], rates: [Int]) -> [Take] {
        let lines = sentences.map(manifestSafe).filter { !$0.isEmpty }
        return lines.enumerated().flatMap { index, text in
            voices.flatMap { voice in
                rates.map { rate in
                    Take(
                        text: text, voice: voice, rate: rate, file: "\(index)-\(slug(voice.name))-\(rate).wav"
                    )
                }
            }
        }
    }

    /// The tab-separated manifest `harvest-confusions` reads, one take per line.
    package static func manifest(_ takes: [Take]) -> String {
        takes.map { take in
            let entry = take.entry
            return [entry.audio, entry.reference, entry.group, entry.speaker].joined(separator: "\t")
        }.joined(separator: "\n") + "\n"
    }

    /// `text` on one line with no tab, since the manifest separates fields with tabs and clips with newlines.
    static func manifestSafe(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `name` lowercased with every character outside a-z and 0-9 dropped, safe in a file name.
    static func slug(_ name: String) -> String {
        String(
            name.lowercased().unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) })
    }
}
