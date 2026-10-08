import UttrflowCore

/// The finished transcript and the joiner's seam stops, which the snippet expander reads past.
struct SeamSnippetInput: Sendable {
    let text: String
    let removableStops: [Int]
    let source: String

    func removingSeamStops() -> String {
        var result = source
        for index in removableStops.reversed() where index < result.count {
            result.remove(at: result.index(result.startIndex, offsetBy: index))
        }
        return result
    }

    /// The expansion with each seam stop back after its word, where the snippets left both sides of the seam alone.
    func restoringUnconsumedStops(in expanded: ExpandedTranscript) -> ExpandedTranscript {
        let stopFree = removingSeamStops()
        // The expander saw the text without the seam stops, so an unchanged answer equals that, not the source.
        guard expanded.text != stopFree else { return .unchanged(text) }
        let text = expanded.text
        let written = text.spokenWords
        let landed = WordErrorRate.measure(
            reference: stopFree.spokenWords.map(String.init), hypothesis: written.map(String.init)
        ).matchedColumns
        let stops = seamWords(in: stopFree).compactMap { word -> String.Index? in
            guard let column = landed[word] else { return nil }
            let end = written[column].endIndex
            return end < text.endIndex && text[end].isWhitespace ? end : nil
        }
        var result = ""
        var copied = text.startIndex
        for stop in stops {
            result += text[copied..<stop]
            result += "."
            copied = stop
        }
        result += text[copied...]
        // A caret at a seam stays before its stop, on the word the snippet put it after.
        let caret = expanded.caret.map { caret in
            caret + stops.count { text.utf16.distance(from: text.startIndex, to: $0) < caret }
        }
        return ExpandedTranscript(text: result, snippets: expanded.snippets, caret: caret)
    }

    /// The index of the word each seam stop follows in `stopFree`, the text the expander was given.
    private func seamWords(in stopFree: String) -> [Int] {
        let ends = stopFree.spokenWords.map { stopFree.distance(from: stopFree.startIndex, to: $0.endIndex) }
        return removableStops.sorted().enumerated().compactMap { earlier, stop in
            ends.firstIndex(of: stop - earlier)
        }
    }
}
