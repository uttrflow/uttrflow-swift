/// The word at the end of a command line, and the line it has to be put back into.
struct CompletionToken: Equatable {
    /// Everything before the word, kept because a candidate carries the whole line.
    let leading: String
    /// The word being completed, never empty.
    let token: String

    /// A word anywhere in a line, for the words a completion adds behind the one being typed.
    init(leading: String, token: String) {
        self.leading = leading
        self.token = token
    }

    /// The word a line ends on, absent when it ends on a space and there is nothing to finish.
    init?(_ typed: String) {
        guard let last = typed.split(separator: " ", omittingEmptySubsequences: false).last,
            !last.isEmpty
        else { return nil }
        leading = String(typed.dropLast(last.count))
        token = String(last)
    }
}
