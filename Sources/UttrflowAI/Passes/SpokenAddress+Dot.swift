import UttrflowCore

extension SpokenAddress {
    /// Reads names joined by a spoken "dot" at a command line, as a module or file whose ending the lists do not know: "http dot server" is "http.server".
    static func readDottedName(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        // A command line's first word is its command, so only a later word opens a name.
        guard expecting.contains(.paths), position > 0,
            let name = part(from: position, within: run, in: live, of: draft), name.labels.count > 1,
            name.labels.allSatisfy({ isNameLabel($0) }),
            FunctionWords.isContent(name.labels[0].lowercased())
        else { return nil }
        let span = position..<(position + name.length)
        guard onlyEndsAreMarked(span, in: live, of: draft) else { return nil }
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(length: span.count, text: first.prefix + name.spelled + last.suffix)
    }

    /// Whether a label is a word of a name: it holds a letter, it is no number, and it is not the spoken dot of an ellipsis.
    private static func isNameLabel(_ label: String) -> Bool {
        let key = label.lowercased()
        return label.contains(where: \.isLetter) && !NumberWords.isNumber(key) && key != "dot"
    }

    /// Reads one or two spoken dots that end a command line, the current or the parent directory: "git add dot" is "git add .".
    static func readDirectoryArgument(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        guard expecting.contains(.paths), position > 0 else { return nil }
        let dots = (position..<run.upperBound).prefix { draft.shape(at: live[$0]).key == "dot" }
        guard (1...2).contains(dots.count), position + dots.count == run.upperBound,
            draft.shape(at: live[position - 1]).key != "dot",
            !MentionGuard.phraseOpeners.contains(draft.shape(at: live[position - 1]).key),
            FunctionWords.isContent(draft.shape(at: live[position - 1]).key),
            draft.shape(at: live[position - 1]).suffix.isEmpty
        else { return nil }
        let span = position..<run.upperBound
        guard span.allSatisfy({ draft.shape(at: live[$0]).prefix.isEmpty }),
            span.dropLast().allSatisfy({ draft.shape(at: live[$0]).suffix.isEmpty }),
            draft.shape(at: live[span.upperBound - 1]).suffix.isEmpty
        else { return nil }
        return SpokenAddress(length: span.count, text: String(repeating: ".", count: dots.count))
    }
}
