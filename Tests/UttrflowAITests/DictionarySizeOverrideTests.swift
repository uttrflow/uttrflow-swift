// False overrides and missed corrections against dictionaries of 0 to 3,000 invented words. See Docs/dictation-quality.md.

import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary
import UttrflowEval

@testable import UttrflowAI

/// The sizes measured, stated once so the report and the checks quote the same ones.
private let sizes = [0, 30, 300, 3_000]

/// Dictionaries drawn per size, so the sentence set is weighed against several arrangements of sound-alikes.
private let draws = 5

private let confidence = 0.95

/// The most false overrides per thousand persona-free words that any size may add over the empty dictionary.
private let ceilingOverEmptyPerThousand = 6.0

/// A seeded source, so every run builds the same invented words.
private struct Stream {
    var state: UInt64

    mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }
}

private let consonants = ["b", "d", "f", "g", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
private let vowels = ["a", "e", "i", "o", "u"]

/// A pronounceable word that is no one's name: two or three consonant-vowel syllables.
private func invented(_ stream: inout Stream) -> String {
    (0..<(2 + stream.next(2))).map { _ in
        consonants[stream.next(consonants.count)] + vowels[stream.next(vowels.count)]
    }.joined()
}

/// Every word the held-out sentences doubt, which is where a sound-alike entry can do harm.
private let doubtedWords: [String] = Set(
    heldOut.flatMap { sentence in
        sentence.split(separator: " ").filter { $0.hasPrefix("*") }.map { String($0.dropFirst().dropLast()) }
    }
).sorted()

/// Invented words sounding like a doubted word: one vowel changed, or a vowel and a trailing letter added.
private func soundAlikes(of word: String) -> [String] {
    var found: [String] = []
    let letters = Array(word)
    for (position, letter) in letters.enumerated() where vowels.contains(String(letter)) {
        for vowel in vowels where vowel != String(letter) {
            var changed = letters
            changed[position] = Character(vowel)
            found.append(String(changed))
        }
    }
    found += vowels.flatMap { vowel in ["m", "z", "k"].map { word + vowel + $0 } }
    return found
}

/// The entry for a spelling, added by hand, with one fixed date so bucket order never varies.
private func entry(_ word: String, sounding: String? = nil) -> DictionaryEntry {
    DictionaryEntry(
        word: word, pronunciations: sounding.map { [$0] } ?? [], origin: .added,
        firstSeen: Date(timeIntervalSince1970: 0))
}

/// The terms a person has said, each heard as a near-sound, that the dictionary must still win back.
private func probeTerms(_ stream: inout Stream) -> [(term: String, heard: String)] {
    (0..<20).map { _ in
        let term = invented(&stream)
        return (term, term + "e")
    }
}

/// A dictionary of `size` invented words: half sound-alikes of doubted corpus words, the rest unrelated; probe terms included.
private func dictionary(size: Int, seed: Int, probes: [(term: String, heard: String)]) -> PhoneticIndex {
    var stream = Stream(state: UInt64(seed) &* 7_919 &+ UInt64(size))
    var words: Set<String> = []
    let clusters = doubtedWords.flatMap(soundAlikes(of:))
    var order = Array(clusters.indices)
    for position in order.indices.reversed() {
        order.swapAt(position, stream.next(position + 1))
    }
    for index in order.prefix(size / 2) { words.insert(clusters[index]) }
    while words.count < size { words.insert(invented(&stream)) }
    let filler = words.sorted().map { entry($0) }
    return PhoneticIndex(entries: filler + probes.map { entry($0.term) })
}

/// What one size produced, summed over every draw.
private struct SizeScore {
    let size: Int
    var words = 0
    var weighed = 0
    var falseOverrides = 0
    var abstained = 0
    var probes = 0
    var fixed = 0
    /// Probes whose term was not among the candidates for what was heard, so no gate could have won it back.
    var unreachable = 0

    var falseOverridesPerThousand: Double { Double(falseOverrides) * 1_000 / Double(words) }
    var upperBoundPerThousand: Double {
        RiskBound.upperBound(failures: falseOverrides, trials: words, confidence: confidence) * 1_000
    }
    var abstentionRate: Double { weighed == 0 ? 0 : Double(abstained) / Double(weighed) }
    var missedShare: Double { Double(probes - fixed) / Double(probes) }
}

/// The held-out sentences as the recogniser could report them: as starred, and with every word doubted.
private func heldOutUtterances() -> [Utterance] {
    heldOut.flatMap { sentence -> [Utterance] in
        let tokens = sentence.split(separator: " ").map { String($0) }
        let starred = tokens.map { token in
            token.hasPrefix("*")
                ? SpokenWord(text: String(token.dropFirst().dropLast()), confidence: 0.3)
                : SpokenWord(text: token, confidence: 0.95)
        }
        let all = tokens.map { SpokenWord(text: $0.replacingOccurrences(of: "*", with: ""), confidence: 0.3) }
        return [Utterance(words: starred), Utterance(words: all)]
    }
}

private func measure(size: Int) -> SizeScore {
    var score = SizeScore(size: size)
    let engine = WordCorrectionEngine()
    var stream = Stream(state: 4_297)
    let probes = probeTerms(&stream)
    for seed in 0..<draws {
        let index = dictionary(size: size, seed: seed, probes: probes)
        for spoken in heldOutUtterances() {
            let verdict = engine.verdict(for: spoken, against: index)
            score.words += spoken.words.count
            score.falseOverrides += verdict.proposals.reduce(0) { $0 + $1.wordRange.count }
            score.abstained += verdict.held.count
            score.weighed += verdict.held.count + verdict.proposals.count
        }
        for probe in probes {
            let spoken = Utterance(
                words: ["send", "it", "to"].map { SpokenWord(text: $0, confidence: 0.95) }
                    + [SpokenWord(text: probe.heard, confidence: 0.3)]
                    + [SpokenWord(text: "today", confidence: 0.95)])
            score.probes += 1
            if !index.candidates(soundingLike: probe.heard).contains(where: { $0.word == probe.term }) {
                score.unreachable += 1
            }
            let fixedHere = engine.proposals(for: spoken, against: index).contains {
                $0.replacement == probe.term
            }
            if fixedHere { score.fixed += 1 }
        }
    }
    return score
}

@Suite("False overrides against dictionaries of growing size")
struct DictionarySizeOverrideTests {
    @Test("No dictionary size adds false overrides on persona-free speech past the ceiling")
    func sizeDoesNotRaiseFalseOverrides() {
        let scores = sizes.map(measure(size:))
        for score in scores {
            print(
                "Dictionary size \(score.size): words \(score.words), weighed \(score.weighed), "
                    + "false overrides \(score.falseOverrides) "
                    + "(\(String(format: "%.2f", score.falseOverridesPerThousand)) per 1,000 words, "
                    + "upper bound \(String(format: "%.2f", score.upperBoundPerThousand)) at 95%), "
                    + "abstained \(score.abstained) (\(String(format: "%.1f", score.abstentionRate * 100))%), "
                    + "missed \(score.probes - score.fixed) of \(score.probes), "
                    + "of which out of reach \(score.unreachable)")
        }
        let empty = scores[0]
        for score in scores {
            let added = score.falseOverridesPerThousand - empty.falseOverridesPerThousand
            #expect(added <= ceilingOverEmptyPerThousand, "size \(score.size)")
        }
    }
}
