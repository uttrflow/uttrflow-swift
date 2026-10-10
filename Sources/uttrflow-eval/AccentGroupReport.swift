// The `accent-groups` command: per-group rates over a local real-speaker slice, with speaker-resampled intervals.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Decodes a seeded sample of a locally downloaded slice, or reads its per-clip counts, and prints the per-group report.
struct AccentGroupReport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accent-groups",
        abstract:
            "Report error and false-override rates per accent group, resampling speakers, from a local slice.",
        discussion: """
            Give exactly one of --manifest (the `harvest-confusions` manifest of downloaded clips, decoded \
            here) or --rows (a counts table already scored). Nothing is fetched and no audio is written.
            """
    )

    @Option(
        name: .long,
        help:
            "Tab-separated rows: speaker, group, label (verified or self-described), errors, words, decisions, false overrides."
    )
    var rows: String?

    @Option(name: .long, help: "Tab-separated clips: audio path, reference text, accent group, speaker.")
    var manifest: String?

    @Option(name: .long, help: "Where the manifest's group labels come from: verified or self-described.")
    var label: String?

    @Option(name: .long, help: "The dataset's name, printed above the report.")
    var dataset: String?

    @Option(
        name: .customLong("dataset-version"),
        help: "The dataset's version or release, printed above the report.")
    var datasetVersion: String?

    @Option(name: .long, help: "The seed that picks each group's clips.")
    var seed: UInt64 = 1

    @Option(name: .long, help: "Clips decoded per group, spread over as many speakers as the group has.")
    var clipsPerGroup = 200

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "The false-override rate each row must be able to bound.")
    var decisionBound = 0.001

    func validate() throws {
        guard (rows == nil) != (manifest == nil) else {
            throw ValidationError("give exactly one of --rows or --manifest")
        }
        guard manifest != nil else { return }
        guard label.flatMap(AccentLabelKind.init(rawValue:)) != nil else {
            throw ValidationError("--manifest needs --label verified or --label self-described")
        }
        guard dataset != nil, datasetVersion != nil else {
            throw ValidationError(
                "--manifest needs --dataset and --dataset-version, so the table can be reproduced")
        }
        guard clipsPerGroup > 0 else { throw ValidationError("--clips-per-group must be positive") }
    }

    func run() async throws {
        let clips = if let manifest { try await decoded(manifest) } else { try counted(rows ?? "") }
        SpeakerGroupReport(clips: clips, decisionBound: decisionBound).lines.forEach { print($0) }
    }

    /// Decodes each group's seeded sample with the shipping recogniser and keeps only its counts.
    private func decoded(_ manifest: String) async throws -> [SpeakerClip] {
        let kind = label.flatMap(AccentLabelKind.init(rawValue:)) ?? .selfDescribed
        let (engine, utterances) = try await ManifestDecoder.decode(
            manifest: manifest, modelVariant: modelVariant
        ) {
            AccentSlice.sample($0, perGroup: clipsPerGroup, seed: seed)
        }
        print(
            "\(dataset ?? "") \(datasetVersion ?? ""); \(kind.rawValue) labels; seed \(seed); "
                + "up to \(clipsPerGroup) clips per group; \(engine)")
        return utterances.map { AccentSlice.clip($0, label: kind) }
    }

    /// Reads a counts table: speaker, group, label kind, errors, words, decisions, false overrides.
    private func counted(_ rows: String) throws -> [SpeakerClip] {
        guard let data = FileManager.default.contents(atPath: rows),
            let text = String(data: data, encoding: .utf8)
        else { throw ValidationError("cannot read the counts table at \(rows)") }
        var clips: [SpeakerClip] = []
        for (number, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7, let label = AccentLabelKind(rawValue: fields[2]),
                let errors = Int(fields[3]), let words = Int(fields[4]), let decisions = Int(fields[5]),
                let overrides = Int(fields[6])
            else { throw ValidationError("line \(number + 1) is not a counts row") }
            clips.append(
                SpeakerClip(
                    speaker: fields[0], group: fields[1], label: label, errors: errors, words: words,
                    decisions: decisions, falseOverrides: overrides))
        }
        return clips
    }
}
