// The ordinary words that really are said the same way, which a sound key cannot tell from a collision.

internal import Foundation

/// Words pronounced alike, kept by hand because Double Metaphone files "main" with "man" as readily as "hear" with "here".
public enum Homophones {
    /// Whether two ordinary words are the same sound, which is what makes one a reading of the other.
    public static func share(_ word: String, _ other: String) -> Bool {
        let word = lookupKey(word)
        let other = lookupKey(other)
        guard word != other else { return false }
        return group(containing: word)?.contains(where: { lookupKey($0) == other }) == true
    }

    /// Returns the hand-kept sound-alike spellings for one word, including the word itself.
    public static func group(containing word: String) -> [String]? {
        index[lookupKey(word)]
    }

    /// Each spelling's group, keyed once, so a lookup costs one hash rather than a pass over every group.
    private static let index: [String: [String]] = groups.reduce(into: [:]) { index, group in
        for spelling in group where index[lookupKey(spelling)] == nil { index[lookupKey(spelling)] = group }
    }

    /// Keeps apostrophes inside a spelling, where they distinguish words such as "its" and "it's".
    static func lookupKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .filter { $0.isLetter || $0.isNumber || $0 == "'" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }

    /// Spellings said identically, most frequent first; a pair whose vowels differ at all — "main" and "man" — belongs in none.
    static let groups: [[String]] = [
        ["allowed", "aloud"], ["bored", "board"], ["brake", "break"], ["capital", "capitol"],
        ["by", "buy", "bye"], ["cache", "cash"], ["cell", "sell"], ["sent", "cent", "scent"],
        ["site", "sight", "cite"], ["complement", "compliment"], ["die", "dye"],
        ["fair", "fare"], ["ate", "eight"], ["flew", "flu"], ["flour", "flower"],
        ["for", "four"], ["hear", "here"], ["hole", "whole"], ["hour", "our"],
        ["its", "it's"], ["lets", "let's"], ["knew", "new"], ["knight", "night"], ["know", "no"],
        ["mail", "male"], ["made", "maid"], ["meat", "meet"], ["need", "knead"],
        ["one", "won"], ["pain", "pane"], ["pair", "pear"], ["peace", "piece"], ["peak", "peek"],
        ["plain", "plane"], ["principal", "principle"], ["rain", "reign", "rein"],
        ["road", "rode"], ["root", "route"], ["role", "roll"], ["sail", "sale"], ["scene", "seen"],
        ["sea", "see"], ["son", "sun"], ["stationary", "stationery"], ["steal", "steel"],
        ["tail", "tale"], ["there", "their", "they're"], ["threw", "through"], ["to", "too", "two"],
        ["toe", "tow"], ["vain", "vein"], ["wait", "weight"], ["way", "weigh"],
        ["wear", "where"], ["weather", "whether"], ["weak", "week"],
        ["wood", "would"], ["right", "write", "rite"],
        ["your", "you're"],
    ]
}
