import UttrflowCore

/// Words that mean the word after them is being talked about rather than dictated.
enum MentionGuard {
    static let determiners: Set<String> = [
        "a", "an", "the", "put", "add", "insert", "with", "no", "this", "that", "each", "every",
        "my", "your", "his", "her", "its", "their", "our", "another", "any", "some", "same",
    ]

    /// Whether the mark word at `position` in `live` is mentioned rather than used.
    static func isMentioned(at position: Int, spanning length: Int, in live: [Int], of draft: Draft) -> Bool {
        guard position > 0 else { return true }
        if determiners.contains(draft.shape(at: live[position - 1]).key) { return true }
        let next = position + length
        return next < live.count && draft.shape(at: live[next]).key == "of"
    }
}
