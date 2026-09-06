/// One run of word characters in a piece of text, with its range, so a replacement lands on those words only.
public struct SnippetWordRun: Equatable, Sendable {
    /// The characters as written, case and all.
    public let text: String
    /// Where the run sits in the text it came from.
    public let range: Range<String.Index>
}

/// The word-run split snippet matching is built on.
extension String {
    /// Every maximal run of letters and digits; an apostrophe separates, so no trigger fires in a possessive.
    public func snippetWordRuns() -> [SnippetWordRun] {
        var runs: [SnippetWordRun] = []
        var start: String.Index?
        var index = startIndex
        while index < endIndex {
            if self[index].isLetter || self[index].isNumber {
                if start == nil { start = index }
            } else if let began = start {
                runs.append(SnippetWordRun(text: String(self[began..<index]), range: began..<index))
                start = nil
            }
            index = self.index(after: index)
        }
        if let began = start {
            runs.append(SnippetWordRun(text: String(self[began...]), range: began..<endIndex))
        }
        return runs
    }
}
