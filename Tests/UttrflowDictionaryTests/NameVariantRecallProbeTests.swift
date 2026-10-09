// Probe: recall at the candidate limit and key collisions for invented names, by origin group.

import Foundation
import Testing

@testable import UttrflowDictionary

/// One synthesised dictation: the name meant, its origin group, the voice and what the recogniser wrote.
private struct HeardName {
    let group: String
    let name: String
    let voice: String
    let heard: String
}

/// Where the probe reads its transcripts; written by `Scripts/name_variant_probe.py`.
private enum NameProbeInput {
    static let path = ProcessInfo.processInfo.environment["UTTRFLOW_NAME_RECALL"]
    static var isRunnable: Bool { path.map(FileManager.default.fileExists) ?? false }
}

/// Runs only when `UTTRFLOW_NAME_RECALL` names a transcript file. See `Docs/name-variant-recall.md`.
@Suite(
    "Probing name recall by origin",
    .enabled(if: NameProbeInput.isRunnable, "set UTTRFLOW_NAME_RECALL to the probe's TSV"))
struct NameVariantRecallProbe {
    @Test("prints recall@24 on misheard names and key collisions per origin group")
    func probe() throws {
        let rows = try String(contentsOfFile: NameProbeInput.path ?? "", encoding: .utf8)
            .split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
            .filter { $0.count == 4 }
            .map { HeardName(group: String($0[0]), name: String($0[1]), voice: String($0[2]), heard: String($0[3])) }
        let names = Array(Set(rows.map(\.name))).sorted()
        let entries = names.map {
            DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        }
        let index = PhoneticIndex(entries: entries)
        let keyOwners = Dictionary(grouping: names.flatMap { name in
            Set(PronunciationCoder.keys(for: name)).map { ($0, name) }
        }, by: \.0).mapValues { Set($0.map(\.1)) }
        let groupOf = Dictionary(rows.map { ($0.name, $0.group) }, uniquingKeysWith: { first, _ in first })
        print("group\tvoice\tclips\texact\tmisheard\trecall@24\tcollidingNames")
        for group in Set(rows.map(\.group)).sorted() {
            let groupNames = names.filter { groupOf[$0] == group }
            let colliding = groupNames.filter { name in
                PronunciationCoder.keys(for: name).contains { (keyOwners[$0]?.count ?? 0) > 1 }
            }
            for voice in Set(rows.map(\.voice)).sorted() {
                let clips = rows.filter { $0.group == group && $0.voice == voice }
                let misheard = clips.filter { !$0.heard.localizedCaseInsensitiveContains($0.name) }
                let found = misheard.filter { clip in
                    index.candidates(for: Utterance(heard: clip.heard, confidence: 1))
                        .contains { $0.word == clip.name }
                }
                print(
                    "\(group)\t\(voice)\t\(clips.count)\t\(clips.count - misheard.count)\t\(misheard.count)"
                        + "\t\(found.count)/\(misheard.count)\t\(colliding.count)/\(groupNames.count)")
                for clip in misheard where !found.contains(where: { $0.name == clip.name }) {
                    print("  missed\t\(clip.name)\t\(clip.heard)")
                }
            }
        }
        #expect(!rows.isEmpty)
    }
}
