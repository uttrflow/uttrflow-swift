import NaturalLanguage
import UttrflowCore

extension NumberFormsPass {
    /// Product, platform and language names whose next number is their version or model.
    static let versionCarriers = NumberCues.words(for: .versionCarrier)

    /// "python three", "ios sixteen": a carrier straight before the number names it, unless the number counts what follows, "python three small mice".
    static func followsCarrier(at position: Int, count: Int, keys: [String], shapes: [WordShape]) -> Bool {
        guard position > 0, joined(position, shapes), versionCarriers.contains(keys[position - 1]) else {
            return false
        }
        var end = position + count
        // The noun a run counts comes after the whole run: "python three twenty gram mice".
        while joined(end, shapes), NumberWords.isNumber(keys[end]) { end += 1 }
        guard joined(end, shapes) else { return true }
        return !countsWhatFollows(after: end - 1, words: keys, tags: LexicalClass.tags(ofWords: keys))
    }

    /// The classes said between a number and the noun it counts.
    private static let countModifiers: Set<NLTag> = [.adjective, .adverb, .determiner]

    /// Whether the number ending at `end` counts a noun after it, past "of" and any modifiers: "three of the mice", "three small mice".
    static func countsWhatFollows(after end: Int, words: [String], tags: [NLTag?]) -> Bool {
        var head = end + 1
        if tags.indices.contains(head), words[head] == "of" { head += 1 }
        while tags.indices.contains(head), let tag = tags[head], countModifiers.contains(tag) { head += 1 }
        return tags.indices.contains(head) && tags[head] == .noun
    }
}
