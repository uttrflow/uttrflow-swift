// The guard's checks that a rewrite is written in Latin letters, romanises rather than translates, and is not a worked example.
import UttrflowCore

extension MeaningPreservationGuard {
    /// Above this share of words with no counterpart in the romanised draft, a rewrite of Devanagari is a translation.
    static let mostStrangerWords = 0.5
    /// A rewrite this much made of one worked example's words, in order, is that example.
    static let exampleCopied = 0.8

    /// Refuses a rewrite in another script, a translation of a Devanagari draft, or a worked example the draft did not say. See `Docs/latin-output.md`.
    public func scriptVerdict(draft: String, rewritten: String, examples: [String] = []) -> GuardVerdict {
        guard LatinScript.isLatin(rewritten), !Romaniser.containsDevanagari(rewritten) else {
            return .rejected(reason: "the rewrite is not written in the Latin alphabet")
        }
        if let example = Self.echoedExample(draft: draft, rewritten: rewritten, examples: examples) {
            return .rejected(reason: "the rewrite repeats the worked example '\(example)'")
        }
        guard Romaniser.containsDevanagari(draft) else { return .accepted }
        let heard = Set(WordShape.words(Romaniser.romanised(draft)).map(Romaniser.soundKey))
        // A number is the number checks' to judge, whichever way it is written.
        let written = WordShape.words(rewritten).filter { !$0.allSatisfy(\.isNumber) }
        guard !written.isEmpty else { return .accepted }
        let strangers = written.filter { !heard.contains(Romaniser.soundKey($0)) }.count
        guard Double(strangers) <= Double(written.count) * Self.mostStrangerWords else {
            return .rejected(reason: "the rewrite translated the Hindi instead of romanising it")
        }
        return .accepted
    }

    /// The worked example a rewrite copies while the draft does not say it, or `nil`.
    static func echoedExample(draft: String, rewritten: String, examples: [String]) -> String? {
        let written = WordShape.words(rewritten)
        guard written.count >= 3 else { return nil }
        let said = WordShape.words(Romaniser.romanised(draft))
        return examples.first { example in
            let shown = WordShape.words(Romaniser.romanised(example))
            guard shown.count >= 3 else { return false }
            let copied = Double(inOrder(written, shown)) >= Double(written.count) * exampleCopied
            return copied && Double(inOrder(said, shown)) < Double(shown.count) / 2
        }
    }

    /// How many words the two sequences share in the same order, by exact spelling.
    static func inOrder(_ first: [String], _ second: [String]) -> Int {
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: second.count + 1)
        for word in first {
            var current = [0]
            for (index, other) in second.enumerated() {
                current.append(word == other ? previous[index] + 1 : max(previous[index + 1], current[index]))
            }
            previous = current
        }
        return previous[second.count]
    }
}
