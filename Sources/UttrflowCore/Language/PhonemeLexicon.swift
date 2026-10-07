// Words to their sounds and the words within one phoneme of each other, from the bundled pronouncing dictionary.

internal import Foundation

/// A pronouncing dictionary with a one-edit index, so finding every word within weighted phoneme distance 1 is a few hash probes. See `Docs/pronunciation-lexicon.md`.
public struct PhonemeLexicon: Sendable {
    /// One pronunciation: a phoneme number per sound, stress marks dropped.
    typealias Sound = [UInt8]

    /// The cheap substitution cost: one phoneme for another of its class.
    static let nearCost = 0.5

    /// The widest distance `words(within:of:)` finds every word for; the index guarantees nothing wider.
    static let indexedDistance = 1.0

    /// The bundled phoneme classes: one class a line, `#` comments. See `Docs/pronunciation-lexicon.md`.
    static let bundledClasses = bundledText("phoneme-classes", "txt") ?? ""

    /// The lexicon shipped in the app bundle, read once on first use; nil only if the bundle lacks it.
    public static let bundled: PhonemeLexicon? = bundledText("pronunciation-lexicon", "dict")
        .map { PhonemeLexicon(listing: $0) }

    /// A text resource inside this module's bundle; never a remote URL.
    private static func bundledText(_ name: String, _ type: String) -> String? {
        Bundle.module.url(forResource: name, withExtension: type)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// Every word, lower-cased, in the order the listing first names it.
    public let words: [String]

    private let soundsByWord: [String: [Sound]]

    /// Each phoneme number's class: phonemes on one line of the class text share one, any other is its own.
    private let classes: [UInt8]

    /// Word numbers filed under each pronunciation's class sequence and each sequence one phoneme shorter.
    private let index: [Sound: [Int32]]

    /// Reads a listing in the pronouncing dictionary's line format: `word PH ON EMES`, alternatives as `word(2)`, `#` comments, stress digits dropped. A line with a field that is not upper-case letters and an optional digit is skipped, as is any phoneme past the 255th.
    public init(listing text: String) {
        self.init(listing: text, classes: Self.bundledClasses)
    }

    /// Reads a listing with these phoneme classes, one class a line.
    init(listing text: String, classes classText: String) {
        var numbers: [Substring: UInt8] = [:]
        var classes: [UInt8] = []
        func number(_ phone: Substring) -> UInt8? {
            if let known = numbers[phone] { return known }
            guard classes.count < Int(UInt8.max) else { return nil }
            let next = UInt8(classes.count)
            numbers[phone] = next
            classes.append(next)
            return next
        }
        for line in classText.split(whereSeparator: \.isNewline) {
            let members = line.prefix { $0 != "#" }.split(separator: " ").compactMap(number)
            for member in members { classes[Int(member)] = members.first ?? member }
        }
        var order: [String] = []
        var sounds: [String: [Sound]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.prefix { $0 != "#" }.split(separator: " ")
            guard let head = fields.first, fields.count > 1 else { continue }
            let phones = fields.dropFirst().map { $0.prefix { $0.isUppercase && $0.isASCII } }
            guard zip(phones, fields.dropFirst()).allSatisfy({ Self.isPhoneme($0, field: $1) }) else {
                continue
            }
            let sound = phones.compactMap(number)
            guard sound.count == phones.count else { continue }
            let word = head.prefix { $0 != "(" }.lowercased()
            if sounds[word] == nil { order.append(word) }
            if sounds[word]?.contains(sound) != true { sounds[word, default: []].append(sound) }
        }
        self.classes = classes
        var index: [Sound: [Int32]] = [:]
        for (position, word) in order.enumerated() {
            var keys: Set<Sound> = []
            for sound in sounds[word] ?? [] { keys.formUnion(Self.indexKeys(for: sound, classes: classes)) }
            for key in keys { index[key, default: []].append(Int32(position)) }
        }
        self.words = order
        self.soundsByWord = sounds
        self.index = index
    }

    /// Whether a field is its upper-case letters followed by at most one stress digit.
    private static func isPhoneme(_ letters: Substring, field: Substring) -> Bool {
        let rest = field.dropFirst(letters.count)
        return !letters.isEmpty && rest.count <= 1 && rest.allSatisfy(\.isNumber)
    }

    /// Whether the lexicon lists a pronunciation for the word, case folded.
    public func holds(_ word: String) -> Bool {
        soundsByWord[word.lowercased()] != nil
    }

    /// The listed pronunciations of a word, case folded; empty when the lexicon does not hold it.
    func sounds(of word: String) -> [Sound] {
        soundsByWord[word.lowercased()] ?? []
    }

    /// The least distance between any pronunciation of one word and any of the other; nil when either is unlisted.
    public func distance(_ word: String, _ other: String) -> Double? {
        let first = sounds(of: word)
        let second = sounds(of: other)
        guard !first.isEmpty, !second.isEmpty else { return nil }
        return first.flatMap { one in second.map { distance(one, $0) } }.min()
    }

    /// Every other word within `limit` (at most `indexedDistance`, 1) of any pronunciation of `word`, nearest first, then alphabetically.
    public func words(within limit: Double = 1, of word: String) -> [String] {
        let folded = word.lowercased()
        return words(within: limit, ofSounds: sounds(of: folded)).filter { $0 != folded }
    }

    /// Every listed word within `limit` (at most `indexedDistance`) of any of these pronunciations, nearest first, then alphabetically.
    func words(within limit: Double = PhonemeLexicon.indexedDistance, ofSounds heard: [Sound]) -> [String] {
        let cap = Int((min(limit, Self.indexedDistance) * 2).rounded(.down))
        guard cap >= 0 else { return [] }
        var reached: Set<Int32> = []
        for sound in heard {
            for key in Self.indexKeys(for: sound, classes: classes) {
                for number in index[key] ?? [] { reached.insert(number) }
            }
        }
        var found: [(word: String, halves: Int)] = []
        for number in reached {
            let word = words[Int(number)]
            var nearest = cap + 1
            for listed in soundsByWord[word] ?? [] {
                for sound in heard { nearest = min(nearest, halfCosts(sound, listed, cap: cap)) }
            }
            if nearest <= cap { found.append((word, nearest)) }
        }
        return found.sorted { ($0.halves, $0.word) < ($1.halves, $1.word) }.map(\.word)
    }

    /// Weighted edit distance: one phoneme for another of its class costs `nearCost`, any other substitution, insertion or deletion costs 1.
    func distance(_ first: Sound, _ second: Sound) -> Double {
        Double(halfCosts(first, second, cap: Int.max / 4)) / 2
    }

    /// The distance in half units, or `cap + 1` as soon as every alignment is known to cost more than `cap`.
    func halfCosts(_ first: Sound, _ second: Sound, cap: Int) -> Int {
        if abs(first.count - second.count) * 2 > cap { return cap + 1 }
        let width = second.count + 1
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: width * 2) { buffer in
            guard var previous = buffer.baseAddress else { return cap + 1 }
            var current = previous + width
            for column in 0..<width { previous[column] = column * 2 }
            for (row, phone) in first.enumerated() {
                current[0] = (row + 1) * 2
                var rowBest = current[0]
                for (column, other) in second.enumerated() {
                    let substitution = previous[column] + halfCost(phone, other)
                    let value = min(previous[column + 1] + 2, current[column] + 2, substitution)
                    current[column + 1] = value
                    rowBest = min(rowBest, value)
                }
                if rowBest > cap { return cap + 1 }
                swap(&previous, &current)
            }
            return min(previous[width - 1], cap + 1)
        }
    }

    /// The cost of hearing one phoneme as another, in half units.
    func halfCost(_ first: UInt8, _ second: UInt8) -> Int {
        if first == second { return 0 }
        return classes[Int(first)] == classes[Int(second)] ? 1 : 2
    }

    /// The class sequence and every sequence one class shorter. Within distance 1 there is at most one full-cost edit, and near-cost substitutions keep the class, so two such sounds always share a key.
    static func indexKeys(for sound: Sound, classes: [UInt8]) -> Set<Sound> {
        let classed = sound.map { classes[Int($0)] }
        var keys: Set<Sound> = [classed]
        for position in classed.indices {
            var shorter = classed
            shorter.remove(at: position)
            keys.insert(shorter)
        }
        return keys
    }
}
