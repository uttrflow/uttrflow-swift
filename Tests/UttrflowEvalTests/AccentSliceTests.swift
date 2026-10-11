// Tests the real-speaker slice: manifest parsing, the seeded per-group sample, and per-clip counts.
import Testing

@testable import UttrflowEval

@Suite("The accent slice")
struct AccentSliceTests {
    /// An invented manifest: `speakers` speakers per group, each reading `clips` clips.
    private func manifest(groups: [String], speakers: Int, clips: Int) -> String {
        groups.flatMap { group in
            (0..<speakers).flatMap { speaker in
                (0..<clips).map { clip in
                    "\(group)/\(speaker)-\(clip).wav\tthe cat sat\t\(group)\t\(group)-\(speaker)"
                }
            }
        }.joined(separator: "\n")
    }

    @Test("reads four-field lines and skips shorter ones")
    func parses() {
        let entries = AccentSlice.entries(
            "a.wav\tone two\tnorth\ts1\nbroken line\nb.wav\tthree\tsouth\ts2\textra\n")
        #expect(
            entries == [
                AccentSlice.Entry(audio: "a.wav", reference: "one two", group: "north", speaker: "s1"),
                AccentSlice.Entry(audio: "b.wav", reference: "three", group: "south", speaker: "s2"),
            ])
    }

    @Test("takes the same clips per group for the same seed, and others for another")
    func seeded() {
        let entries = AccentSlice.entries(manifest(groups: ["north", "south"], speakers: 10, clips: 10))
        let first = AccentSlice.sample(entries, perGroup: 15, seed: 7)
        #expect(first == AccentSlice.sample(entries, perGroup: 15, seed: 7))
        #expect(first != AccentSlice.sample(entries, perGroup: 15, seed: 8))
        #expect(first.count { $0.group == "north" } == 15)
        #expect(first.count { $0.group == "south" } == 15)
        #expect(first == entries.filter(first.contains))
    }

    @Test("spreads the budget over every speaker before taking a second clip from any")
    func spreadsOverSpeakers() {
        let entries = AccentSlice.entries(manifest(groups: ["east"], speakers: 12, clips: 5))
        let sample = AccentSlice.sample(entries, perGroup: 12, seed: 1)
        #expect(Set(sample.map(\.speaker)).count == 12)
        let wider = AccentSlice.sample(entries, perGroup: 30, seed: 1)
        let perSpeaker = Dictionary(grouping: wider, by: \.speaker).mapValues(\.count)
        #expect(perSpeaker.values.allSatisfy { $0 == 2 || $0 == 3 })
        #expect(AccentSlice.sample(entries, perGroup: 500, seed: 1) == entries)
    }

    @Test("a decoded clip carries word errors over reference words and its speaker and group")
    func counts() {
        let utterance = HarvestUtterance(
            reference: ["the", "very", "wet", "van"], recognised: ["the", "wery", "wet"], group: "west",
            speaker: "west-1")
        let clip = AccentSlice.clip(utterance, label: .verified)
        #expect(clip == SpeakerClip(speaker: "west-1", group: "west", label: .verified, errors: 2, words: 4))
    }
}
