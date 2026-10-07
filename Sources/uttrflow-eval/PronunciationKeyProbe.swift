// The `pronunciation-keys` command: the letter-derived sound key against phoneme distance, on one pair set.
import ArgumentParser
private import Foundation
private import UttrflowDictionary

/// Compares the shipped candidate chain with weighted phoneme distance over a public pronouncing dictionary.
struct PronunciationKeyProbe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pronunciation-keys",
        abstract: "Measure the sound key and phoneme distance on the same pairs. See Docs/cleanup.md."
    )

    @Option(name: .long, help: "A CMU Pronouncing Dictionary file (cmudict.dict format).")
    var lexicon: String

    @Option(name: .long, help: "Words one per line, most frequent first.")
    var words: String

    @Option(name: .long, help: "How many of the most frequent words form the pair set.")
    var top = 10_000

    func run() throws {
        let pronunciations = try Self.pronunciations(from: lexicon)
        let ranked = try String(contentsOfFile: words, encoding: .utf8)
            .split(whereSeparator: \.isNewline).map { $0.lowercased() }
            .filter { pronunciations[$0] != nil }
        let chosen = Array(ranked.prefix(top))
        let table = PronunciationComparison(words: chosen, pronunciations: pronunciations)
        print(table.report())
        let sizeWords = Array(pronunciations.keys.sorted().prefix(30_000))
        let bytes = sizeWords.reduce(0) { total, word in
            total + word.utf8.count + (pronunciations[word]?.first?.count ?? 0) + 2
        }
        print(
            "lexicon of \(sizeWords.count) words, one pronunciation each, one byte a phoneme: \(bytes / 1024) KiB"
        )
    }

    /// Each word's pronunciations, stress marks dropped, alternative listings merged under the word.
    static func pronunciations(from path: String) throws -> [String: [[String]]] {
        var found: [String: [[String]]] = [:]
        for line in try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "#")[0].split(separator: " ")
            guard let head = parts.first else { continue }
            let word = head.split(separator: "(")[0].lowercased()
            let phones = parts.dropFirst().map { $0.filter(\.isLetter) }
            found[word, default: []].append(phones)
        }
        return found
    }
}

/// Both mechanisms scored against the pronouncing dictionary as the oracle.
struct PronunciationComparison {
    let words: [String]
    let pronunciations: [String: [[String]]]

    private static let vowels: Set<String> = [
        "AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW",
    ]
    private static let voicing: Set<Set<String>> = [
        ["P", "B"], ["T", "D"], ["K", "G"], ["F", "V"], ["S", "Z"], ["TH", "DH"], ["SH", "ZH"], ["CH", "JH"],
    ]

    /// Substitution cost: half for one vowel for another or a voicing pair, one otherwise.
    static func cost(_ first: String, _ second: String) -> Double {
        if first == second { return 0 }
        if vowels.contains(first) && vowels.contains(second) { return 0.5 }
        if voicing.contains([first, second]) { return 0.5 }
        return 1
    }

    /// Weighted edit distance between two phoneme sequences.
    static func distance(_ first: [String], _ second: [String]) -> Double {
        var previous = (0...second.count).map(Double.init)
        for (row, phone) in first.enumerated() {
            var current = [Double(row + 1)]
            for (column, other) in second.enumerated() {
                current.append(
                    min(previous[column + 1] + 1, current[column] + 1, previous[column] + cost(phone, other)))
            }
            previous = current
        }
        return previous[second.count]
    }

    /// The least distance between any listing of one word and any listing of the other.
    func distance(_ first: String, _ second: String) -> Double {
        var best = Double.infinity
        for one in pronunciations[first] ?? [] {
            for other in pronunciations[second] ?? [] { best = min(best, Self.distance(one, other)) }
        }
        return best
    }

    struct Pair: Hashable {
        let first: String
        let second: String
        init(_ one: String, _ other: String) {
            (first, second) = one < other ? (one, other) : (other, one)
        }
    }

    /// Pairs within one unweighted edit of each other, found by deleting each phoneme once.
    func nearPairs() -> Set<Pair> {
        var buckets: [String: Set<String>] = [:]
        for word in words {
            for phones in pronunciations[word] ?? [] {
                buckets[phones.joined(separator: " "), default: []].insert(word)
                for index in phones.indices {
                    var shorter = phones
                    shorter.remove(at: index)
                    buckets["-" + shorter.joined(separator: " ") + "#\(index)", default: []].insert(word)
                    buckets[shorter.joined(separator: " "), default: []].insert(word)
                }
            }
        }
        var pairs: Set<Pair> = []
        for bucket in buckets.values where bucket.count > 1 && bucket.count < 400 {
            let members = Array(bucket)
            for one in members.indices {
                for other in members.indices where other > one {
                    pairs.insert(Pair(members[one], members[other]))
                }
            }
        }
        return pairs.filter { distance($0.first, $0.second) <= 1 }
    }

    /// Pairs the shipped key files together.
    func keyPairs() -> Set<Pair> {
        var buckets: [String: [String]] = [:]
        for word in words {
            for key in Set(DoubleMetaphone.code(for: word).keys) { buckets[key, default: []].append(word) }
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

    /// Whether the shipped chain offers one for the other: shared key, opening letters or the hand list, no ordinary collision.
    static func chainOffers(_ pair: Pair) -> Bool {
        (ReadingRestraint.opensAlike(pair.first, heard: pair.second)
            && !ReadingRestraint.isOrdinaryCollision(pair.first, heard: pair.second))
    }

    func report() -> String {
        let near = nearPairs()
        let homophones = near.filter { distance($0.first, $0.second) == 0 }
        let neighbours = near.subtracting(homophones)
        let keyed = keyPairs()
        let chain = keyed.filter(Self.chainOffers)
        let keyedDistances = keyed.map { distance($0.first, $0.second) }
        func percent(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "n/a" : String(format: "%.1f%%", 100 * Double(part) / Double(whole))
        }
        let start = Date()
        var probes = 0
        for word in words.prefix(200) {
            for phones in pronunciations[word] ?? [] {
                for other in words {
                    for listing in pronunciations[other] ?? [] where abs(listing.count - phones.count) <= 1 {
                        _ = Self.distance(phones, listing); probes += 1
                    }
                }
            }
        }
        let perLookup = Date().timeIntervalSince(start) / 200 * 1000
        return """
            words: \(words.count); homophone pairs: \(homophones.count); distance-1 neighbours (weighted <= 1, not 0): \(neighbours.count)
            | Metric | (a) key alone | (a) shipped chain | (b) phoneme distance <= 1 |
            |---|---|---|---|
            | Homophone recall | \(percent(homophones.intersection(keyed).count, homophones.count)) | \(percent(homophones.intersection(chain).count, homophones.count)) | 100% (oracle) |
            | Neighbour recall | \(percent(neighbours.intersection(keyed).count, neighbours.count)) | \(percent(neighbours.intersection(chain).count, neighbours.count)) | 100% (oracle) |
            | Pairs offered | \(keyed.count) | \(chain.count) | \(near.count) |
            | Offered pairs within distance 1 | \(percent(keyedDistances.filter { $0 <= 1 }.count, keyed.count)) | \(percent(chain.filter { distance($0.first, $0.second) <= 1 }.count, chain.count)) | 100% |
            | Offered pairs two or more phonemes apart | \(percent(keyedDistances.filter { $0 >= 2 }.count, keyed.count)) | \(percent(chain.filter { distance($0.first, $0.second) >= 2 }.count, chain.count)) | 0% |
            brute-force distance lookup over \(words.count) words: \(String(format: "%.1f", perLookup)) ms a word (\(probes) comparisons)
            """
    }
}
