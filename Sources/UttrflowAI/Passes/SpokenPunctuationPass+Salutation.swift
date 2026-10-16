import UttrflowCore

extension SpokenPunctuationPass {
    /// The most words a salutation holds before its comma: a two-word opener and a two-word name.
    private static let longestSalutation = 4

    /// Whether the clause so far is a greeting opener and a one or two word name, so a spoken comma after it closes the salutation.
    func closesSalutation(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        (2...Self.longestSalutation).contains { count in
            let start = position - count
            guard start >= 0, start == 0 || draft.shape(at: live[start - 1]).endsClause else { return false }
            let spoken = Array(live[start..<position])
            guard let opener = TerminalStopPass.greetingOpenerLength(spoken, in: draft) else { return false }
            return (1...2).contains(count - opener)
        }
    }
}
