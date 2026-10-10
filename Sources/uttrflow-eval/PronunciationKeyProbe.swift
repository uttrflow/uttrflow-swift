// The `pronunciation-keys` command: the phoneme-class sound key against phoneme distance, on one pair set.
import ArgumentParser
private import Foundation
internal import UttrflowCore
private import UttrflowDictionary


/// Compares the sound key and the shipped key-and-distance gate with weighted phoneme distance over a pronouncing dictionary.

struct PronunciationKeyProbe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pronunciation-keys",
        abstract: "Measure the sound key and phoneme distance on the same pairs. See Docs/cleanup.md."
    )

    @Option(
        name: .long,
        help: "A pronouncing dictionary in cmudict.dict format; the bundled lexicon when omitted.")
    var lexicon: String?

    @Option(name: .long, help: "Words one per line, most frequent first; every lexicon word when omitted.")
    var words: String?

    @Option(name: .long, help: "How many of the most frequent words form the pair set.")
    var top = 10_000

    func run() throws {
        let start = Date()
        guard
            let loaded = try lexicon.map({
                PhonemeLexicon(listing: try String(contentsOfFile: $0, encoding: .utf8))
            })
                ?? PhonemeLexicon.bundled
        else { throw ValidationError("The bundled pronunciation lexicon is missing.") }
        let loadMilliseconds = Date().timeIntervalSince(start) * 1000
        let ranked =
            try words.map { try String(contentsOfFile: $0, encoding: .utf8) }
            .map { $0.split(whereSeparator: \.isNewline).map { $0.lowercased() } } ?? loaded.words
        let chosen = Array(ranked.filter { loaded.holds($0) }.prefix(top))
        print(PronunciationComparison(words: chosen, lexicon: loaded).report())
        print(
            String(
                format: "lexicon of %d words read and indexed in %.1f ms", loaded.words.count,
                loadMilliseconds))
    }
}

/// Both mechanisms scored against the pronouncing dictionary as the oracle.
struct PronunciationComparison {
    let words: [String]
    let lexicon: PhonemeLexicon

    struct Pair: Hashable {
        let first: String
        let second: String
        init(_ one: String, _ other: String) {
            (first, second) = one < other ? (one, other) : (other, one)
        }
    }

    private func distance(_ pair: Pair) -> Double {
        lexicon.distance(pair.first, pair.second) ?? .infinity


    }

    /// Pairs within distance 1 inside the pair set, from the lexicon's index.
    func nearPairs() -> Set<Pair> {
        let chosen = Set(words)
        var pairs: Set<Pair> = []
        for word in words {
            for other in lexicon.words(of: word) where chosen.contains(other) {
                pairs.insert(Pair(word, other))
            }
        }
        return pairs
    }

    /// Pairs the sound key files together.
    func keyPairs() -> Set<Pair> {
        var buckets: [String: [String]] = [:]
        for word in words {
            for key in Set(WordSound(of: word, in: lexicon).keys) { buckets[key, default: []].append(word) }
        }
        var pairs: Set<Pair> = []
        for bucket in buckets.values where bucket.count > 1 {
            for one in bucket.indices {
                for other in bucket.indices where other > one {
                    pairs.insert(Pair(bucket[one], bucket[other]))
                }
            }
        }
        return pairs
    }

    /// Whether the shipped gate offers one for the other: within one phoneme, no ordinary collision.
    func chainOffers(_ pair: Pair) -> Bool {
        lexicon.soundsNear(pair.first, pair.second)
            && !ReadingRestraint.isOrdinaryCollision(pair.first, heard: pair.second)
    }

    /// Index lookups for every word in the pair set, p50 and p95 in milliseconds.
    func lookupTimes() -> (p50: Double, p95: Double) {
        var times: [Double] = []
        for word in words {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = lexicon.words(of: word)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        times.sort()
        guard !times.isEmpty else { return (0, 0) }
        return (times[times.count / 2], times[min(times.count - 1, times.count * 95 / 100)])
    }

    /// Words among the first 200 whose brute-force neighbours the index misses; zero when the index is complete.
    func indexMisses() -> Int {
        words.prefix(200).filter { word in
            let brute = Set(words.filter { $0 != word && (lexicon.distance(word, $0) ?? .infinity) <= 1 })
            return !brute.isSubset(of: Set(lexicon.words(of: word)))
        }.count
    }

    /// Index lookups for every word in the pair set, p50 and p95 in milliseconds.
    func lookupTimes() -> (p50: Double, p95: Double) {
        var times: [Double] = []
        for word in words {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = lexicon.words(of: word)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        times.sort()
        guard !times.isEmpty else { return (0, 0) }
        return (times[times.count / 2], times[min(times.count - 1, times.count * 95 / 100)])
    }

    /// Words among the first 200 whose brute-force neighbours the index misses; zero when the index is complete.
    func indexMisses() -> Int {
        words.prefix(200).filter { word in
            let brute = Set(words.filter { $0 != word && (lexicon.distance(word, $0) ?? .infinity) <= 1 })
            return !brute.isSubset(of: Set(lexicon.words(of: word)))
        }.count
    }

    func report() -> String {
        let near = nearPairs()
        let homophones = near.filter { distance($0) == 0 }
        let neighbours = near.subtracting(homophones)
        let keyed = keyPairs()

        let chain = keyed.filter(chainOffers)

        let keyedDistances = keyed.map(distance)
        let chainDistances = chain.map(distance)
        func percent(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "n/a" : String(format: "%.1f%%", 100 * Double(part) / Double(whole))
        }
        let times = lookupTimes()
        return """
            words: \(words.count); homophone pairs: \(homophones.count); distance-1 neighbours (weighted <= 1, not 0): \(neighbours.count)
            | Metric | (a) key alone | (a) key and gate | (b) phoneme distance <= 1 |
            |---|---|---|---|
            | Homophone recall | \(percent(homophones.intersection(keyed).count, homophones.count)) | \(percent(homophones.intersection(chain).count, homophones.count)) | \(percent(homophones.count, homophones.count)) |
            | Neighbour recall | \(percent(neighbours.intersection(keyed).count, neighbours.count)) | \(percent(neighbours.intersection(chain).count, neighbours.count)) | \(percent(neighbours.count, neighbours.count)) |
            | Pairs offered | \(keyed.count) | \(chain.count) | \(near.count) |
            | Offered pairs within distance 1 | \(percent(keyedDistances.filter { $0 <= 1 }.count, keyed.count)) | \(percent(chainDistances.filter { $0 <= 1 }.count, chain.count)) | 100% |
            | Offered pairs two or more phonemes apart | \(percent(keyedDistances.filter { $0 >= 2 }.count, keyed.count)) | \(percent(chainDistances.filter { $0 >= 2 }.count, chain.count)) | 0% |
            index lookup over \(words.count) words: p50 \(String(format: "%.3f", times.p50)) ms, p95 \(String(format: "%.3f", times.p95)) ms; words of the first 200 the index misses against brute force: \(indexMisses())
            """
    }
}
