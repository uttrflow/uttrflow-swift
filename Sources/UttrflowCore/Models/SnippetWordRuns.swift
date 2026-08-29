/// One run of word characters in a piece of text, and where it sits in it.
///
/// The range travels with the text because a replacement has to land on exactly the
/// words that were said and leave everything around them alone. Matching "my address"
/// in "My address." and then replacing the whole sentence would eat the full stop the
/// tidier had just decided to add.
public struct SnippetWordRun: Equatable, Sendable {
    /// The characters as they were written, case and all.
    public let text: String
    public let range: Range<String.Index>
}

extension String {
    /// Every maximal run of letters and digits, in order.
    ///
    /// This is the whole of the punctuation tolerance. A trigger is *spoken*, so the
    /// only thing it can be lined up against is words; everything the tidier does —
    /// adding a full stop, adding a comma, capitalising the first letter — changes the
    /// separators or the case and never the runs. "My address." and "my address"
    /// therefore produce the same two runs, which is what makes them the same trigger.
    ///
    /// An apostrophe separates rather than joins, so "address's" is two runs and not
    /// one. That reads like a mistake until you follow it through: the trigger
    /// "address" then ends against a separator that ``SnippetExpander`` recognises as
    /// glue, and the snippet refuses to fire inside the possessive. Making the
    /// apostrophe a word character would have needed a second, separate rule to get the
    /// same answer.
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
