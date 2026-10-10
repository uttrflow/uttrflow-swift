// A locally downloaded real-speaker slice: which of its clips are decoded, and the counts a decoded clip gives.
private import UttrflowCore

/// The manifest `harvest-confusions` reads, a seeded sample of it per group, and per-clip counts for the report.
public enum AccentSlice {
    /// One manifest line: audio path, reference text, accent group, speaker.
    public struct Entry: Sendable, Equatable {
        public let audio: String
        public let reference: String
        public let group: String
        public let speaker: String

        public init(audio: String, reference: String, group: String, speaker: String) {
            self.audio = audio
            self.reference = reference
            self.group = group
            self.speaker = speaker
        }
    }

    /// The entries of a tab-separated manifest; a line with fewer than four fields is skipped.
    public static func entries(_ manifest: String) -> [Entry] {
        manifest.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            return Entry(audio: fields[0], reference: fields[1], group: fields[2], speaker: fields[3])
        }
    }

    /// At most `perGroup` entries per group, one clip per speaker per round in seeded order, so the budget reaches every speaker.
    public static func sample(_ entries: [Entry], perGroup: Int, seed: UInt64) -> [Entry] {
        var kept = Set<Int>()
        let byGroup = Dictionary(grouping: entries.indices) { entries[$0].group }
        for indices in byGroup.values {
            let bySpeaker = Dictionary(grouping: indices) { entries[$0].speaker }
            let queues = bySpeaker.keys.sorted { rank($0, seed) < rank($1, seed) }.map { speaker in
                (bySpeaker[speaker] ?? []).sorted {
                    rank(entries[$0].audio, seed) < rank(entries[$1].audio, seed)
                }
            }
            var taken = 0
            var round = 0
            while taken < perGroup, queues.contains(where: { round < $0.count }) {
                for queue in queues where round < queue.count && taken < perGroup {
                    kept.insert(queue[round])
                    taken += 1
                }
                round += 1
            }
        }
        return entries.indices.filter(kept.contains).map { entries[$0] }
    }

    /// One decoded utterance as the report's per-clip counts: word errors over reference words, no words kept.
    public static func clip(_ utterance: HarvestUtterance, label: AccentLabelKind) -> SpeakerClip {
        let rate = WordErrorRate.measure(reference: utterance.reference, hypothesis: utterance.recognised)
        return SpeakerClip(
            speaker: utterance.speaker, group: utterance.group, label: label, errors: rate.errors,
            words: rate.referenceWordCount)
    }

    private static func rank(_ text: String, _ seed: UInt64) -> (UInt64, String) {
        (ConfusionHarvest.stableHash(text, seed: seed), text)
    }
}
