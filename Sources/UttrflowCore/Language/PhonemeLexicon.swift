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

    /// The fewest sounds a pair needs before a whole phoneme apart is still one word misheard when either is read from its spelling; such a shorter pair may differ by one near phoneme only, as two guessed vowels put "chini" a whole phoneme from "khana".
    static let soundsForWholePhoneme = 5

    /// The bundled phoneme classes: one class a line, `#` comments. See `Docs/pronunciation-lexicon.md`.
    static let bundledClasses = bundledText("phoneme-classes", "txt") ?? ""

    /// The bundled sound-key rules: which phonemes a key folds into others and which it drops. See `Docs/pronunciation-lexicon.md`.
    static let bundledKeyRules = bundledText("sound-keys", "txt") ?? ""

    /// The bundled spelling rules for a word the lexicon does not list. See `Docs/pronunciation-lexicon.md`.
    static let bundledSpellingRules = bundledText("letter-sounds", "txt") ?? ""

    /// The lexicon shipped in the app bundle, read once on first use; nil only if the bundle lacks it.
    public static let bundled: PhonemeLexicon? = bundledText("pronunciation-lexicon", "dict")
        .map { PhonemeLexicon(listing: $0) }

    /// The bundled lexicon, or the spelling rules alone if the bundle lacks it, so every caller has one to ask.
    public static let shared: PhonemeLexicon = bundled ?? PhonemeLexicon(listing: "")

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

    /// The spelling rules, in the order they are tried.
    private let spellingRules: [SpellingRule]

    /// The classes a sound key drops after its first sound: the vowels, and the glides and h that lean on them.
    private let keyDrops: Set<UInt8>

    /// The phonemes a sound key reads as other classes: each affricate as its fricative, the r-coloured vowel as a vowel and an r.
    private let keyFolds: [UInt8: [UInt8]]

    /// Reads a listing in the pronouncing dictionary's line format: `word PH ON EMES`, alternatives as `word(2)`, `#` comments, stress digits dropped. A line with a field that is not upper-case letters and an optional digit is skipped, as is any phoneme past the 255th.
    public init(listing text: String) {
        self.init(
            listing: text, classes: Self.bundledClasses, spellingRules: Self.bundledSpellingRules,
            keyRules: Self.bundledKeyRules)
    }

    /// Reads a listing with these phoneme classes, one class a line, these spelling rules and these sound-key rules.
    init(
        listing text: String, classes classText: String, spellingRules ruleText: String = "",
        keyRules keyText: String = ""
    ) {
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
        let rules = ruleText.split(whereSeparator: \.isNewline).compactMap { line in
            SpellingRule(line.prefix { $0 != "#" }, number: number)
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
        self.spellingRules = rules
        var folds: [UInt8: [UInt8]] = [:]
        var drops: Set<UInt8> = []
        func keyClass(_ phone: Substring) -> UInt8? { numbers[phone].map { classes[Int($0)] } }
        for line in keyText.split(whereSeparator: \.isNewline) {
            let fields = line.prefix { $0 != "#" }.split(separator: " ")
            guard let verb = fields.first, let phone = fields.dropFirst().first else { continue }
            if verb == "drop", let dropped = keyClass(phone) { drops.insert(dropped) }
            if verb == "fold", let from = numbers[phone] {
                folds[from] = fields.dropFirst(2).compactMap(keyClass)
            }
        }
        self.keyFolds = folds
        self.keyDrops = drops
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

extension PhonemeLexicon {
    /// The sounds the spelling rules give a word, whatever the lexicon lists: the likelier reading, then a second where a rule offers one. Empty when it has no Latin letter.
    func spelledSounds(of word: String) -> [Sound] {
        let letters = Array(
            Self.latinLetters(word).reduce(into: "") { kept, letter in
                if kept.last != letter || Self.isVowelLetter(letter) { kept.append(letter) }
            })
        var likelier: Sound = []
        var second: Sound = []
        var position = 0
        while position < letters.count {
            guard
                let rule = spellingRules.first(where: {
                    $0.fits(letters, at: position, voiced: !likelier.isEmpty)
                })
            else {
                position += 1
                continue
            }
            likelier += rule.sound
            second += rule.alternate ?? rule.sound
            position += rule.letters.count
        }
        if likelier.isEmpty { return [] }
        return second == likelier ? [likelier] : [likelier, second]
    }

    /// The pronunciations the lexicon gives a word or a run: a single word's every listing, or a run's words each by its first, a word it does not list by its spelling. Empty when nothing is listed.
    private func listedSounds(of words: [String]) -> [Sound] {
        if words.count == 1, let word = words.first { return sounds(of: word) }
        guard words.contains(where: holds) else { return [] }
        return [words.flatMap { sounds(of: $0).first ?? spelledSounds(of: $0).first ?? [] }]
    }

    /// Every sound a text could be, for filing: what the lexicon lists, then what its spelling closed up gives.
    func candidateSounds(of text: String) -> [Sound] {
        let words = Self.spokenWords(in: text)
        return Self.distinct(listedSounds(of: words) + spelledSounds(of: words.joined()))
    }

    /// The sounds a text is measured by: the lexicon's alone when it lists every word, so a spelling rule never loosens a listed word.
    func measuredSounds(of text: String) -> [Sound] {
        let words = Self.spokenWords(in: text)
        let listed = listedSounds(of: words)
        if !words.isEmpty, words.allSatisfy(holds) { return listed }
        return Self.distinct(listed + spelledSounds(of: words.joined()))
    }

    /// The sounds in their first order, each once, none empty.
    private static func distinct(_ sounds: [Sound]) -> [Sound] {
        var seen: Set<Sound> = []
        return sounds.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The keys a word or run is filed and looked up under: each candidate sound as its consonant classes, a leading vowel kept as one mark, so a near vowel or a misheard word break still meets. Empty when nothing in the text makes a sound.
    func soundKeys(of text: String) -> [String] {
        var seen: Set<String> = []
        return candidateSounds(of: text).map(key).filter { seen.insert($0).inserted }
    }

    /// One sound's key: affricates folded into their fricatives, an r-coloured vowel read as a vowel and an r, a repeat read once, and after the first sound the vowels and glides dropped.
    private func key(_ sound: Sound) -> String {
        var classed: [UInt8] = []
        for phone in sound {
            let folded = keyFolds[phone] ?? [classes[Int(phone)]]
            for kind in folded where classed.last != kind { classed.append(kind) }
        }
        let skeleton = classed.enumerated().filter { $0.offset == 0 || !keyDrops.contains($0.element) }.map(
            \.element)
        return String(skeleton.map { Character(Unicode.Scalar($0)) })
    }

    /// The least distance between any measured sound of one text and any of the other; nil when either makes no sound.
    public func soundDistance(_ text: String, _ other: String) -> Double? {
        let first = measuredSounds(of: text)
        let second = measuredSounds(of: other)
        guard !first.isEmpty, !second.isEmpty else { return nil }
        let cap = Int(Self.indexedDistance * 2) + 1
        let halves = first.flatMap { one in second.map { halfCosts(one, $0, cap: cap) } }.min() ?? cap
        return Double(halves) / 2
    }

    /// Whether one text could be the other misheard: within the indexed distance when the lexicon lists both, or when both pronunciations have `soundsForWholePhoneme` sounds; otherwise within one near phoneme, because a spelling rule's guess is itself a phoneme off as often as not.
    public func soundsMisheard(_ text: String, as other: String) -> Bool {
        let cap = Int(Self.indexedDistance * 2)
        let bothListed = isListed(text) && isListed(other)
        let first = measuredSounds(of: text)
        let second = measuredSounds(of: other)
        return first.contains { one in
            second.contains { two in
                let whole = bothListed || min(one.count, two.count) >= Self.soundsForWholePhoneme
                return halfCosts(one, two, cap: cap) <= (whole ? cap : Int(Self.nearCost * 2))
            }
        }
    }

    /// Whether the lexicon lists every word of a text, so it is measured by listing and never by a spelling rule.
    private func isListed(_ text: String) -> Bool {
        let words = Self.spokenWords(in: text)
        return !words.isEmpty && words.allSatisfy(holds)
    }

    /// Whether two texts are within the indexed distance of each other: one phoneme apart, or two near ones.
    public func soundsNear(_ text: String, _ other: String) -> Bool {
        (soundDistance(text, other) ?? .infinity) <= Self.indexedDistance
    }

    /// Whether two differently spelt words are listed with one pronunciation in common: homophones, "hear" and "here".
    public func soundsSame(_ word: String, _ other: String) -> Bool {
        let word = Self.listedSpelling(word)
        let other = Self.listedSpelling(other)
        return word != other && distance(word, other) == 0
    }

    /// The other listed words said exactly like this one, alphabetically, never the word itself with a mark attached ("in."); empty when the lexicon does not list it.
    public func homophones(of word: String) -> [String] {
        let folded = Self.listedSpelling(word)
        return words(within: 0, of: folded).filter { Self.listedSpelling($0) != folded }
    }

    /// A word as the lexicon files it: lower case, a curly apostrophe straightened, marks around it dropped.
    static func listedSpelling(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet.letters.inverted)
    }

    /// The words in a text, each lower case with its apostrophes, accents folded away.
    static func spokenWords(in text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !($0.isASCII && ($0.isLetter || $0 == "'")) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// The Latin letters of a word, lower case, accents folded away; nothing else.
    static func latinLetters(_ word: String) -> String {
        word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isASCII && $0.isLetter }
    }

    /// Whether a letter is one of the five vowel letters, which a doubling never collapses.
    static func isVowelLetter(_ letter: Character) -> Bool {
        "aeiou".contains(letter)
    }
}

/// One line of the spelling rules: letters, where they may stand, and the phonemes they make.
struct SpellingRule: Sendable {
    let letters: [Character]
    let atStart: Bool
    let atEnd: Bool
    /// The letters one of which must come next; empty when anything may.
    let before: Set<Character>
    let sound: PhonemeLexicon.Sound
    /// The second reading where a phoneme has one; nil when the rule reads one way only.
    let alternate: PhonemeLexicon.Sound?

    /// Reads one rule line, numbering its phonemes; nil for a blank line or one with no letters.
    init?(_ line: Substring, number: (Substring) -> UInt8?) {
        let fields = line.split(separator: " ")
        guard var pattern = fields.first else { return nil }
        atStart = pattern.hasPrefix("^")
        if atStart { pattern = pattern.dropFirst() }
        atEnd = pattern.hasSuffix("$")
        if atEnd { pattern = pattern.dropLast() }
        let parts = pattern.split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
        letters = Array(parts.first ?? "")
        before = Set(parts.dropFirst().first ?? "")
        let phones = fields.dropFirst().map { $0.split(separator: "|") }
        sound = phones.compactMap { $0.first.flatMap(number) }
        let second = phones.compactMap { ($0.dropFirst().first ?? $0.first).flatMap(number) }
        alternate = second == sound ? nil : second
        guard !letters.isEmpty else { return nil }
    }

    /// Whether the rule reads the letters at this position; a silent final letter only once something has sounded.
    func fits(_ word: [Character], at position: Int, voiced: Bool) -> Bool {
        let end = position + letters.count
        guard end <= word.count, Array(word[position..<end]) == letters else { return false }
        if atStart, position != 0 { return false }
        if atEnd, end != word.count || (sound.isEmpty && !voiced) { return false }
        if !before.isEmpty, end >= word.count || !before.contains(word[end]) { return false }
        return true
    }
}
