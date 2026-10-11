import UttrflowCore

/// The HTTP words whose case depends on their slot: a method before a path, a reason phrase after its status code.
enum HTTPSlots {
    /// The methods that are everyday words, written in capitals only straight before a path or URL.
    static let methods: Set<String> = ["get", "post", "put", "patch", "delete", "head"]

    /// The words that may stand between a method and its path: "a post to /api/orders".
    static let linkers: Set<String> = ["to", "on"]

    /// Each standard status code with its reason phrase as written.
    static let reasons: [String: [String]] = [
        "200": ["OK"], "201": ["Created"], "204": ["No", "Content"], "301": ["Moved", "Permanently"],
        "302": ["Found"], "304": ["Not", "Modified"], "400": ["Bad", "Request"], "401": ["Unauthorized"],
        "403": ["Forbidden"], "404": ["Not", "Found"], "409": ["Conflict"],
        "422": ["Unprocessable", "Entity"], "429": ["Too", "Many", "Requests"],
        "500": ["Internal", "Server", "Error"], "502": ["Bad", "Gateway"],
        "503": ["Service", "Unavailable"], "504": ["Gateway", "Timeout"],
    ]

    /// Writes each method before a path and each reason phrase after its code in the case a reader expects.
    static func apply(to draft: inout Draft) {
        let live = draft.presentIndices.filter { !draft.words[$0].isLayoutMark }
        for (position, index) in live.enumerated() {
            let shape = draft.shape(at: index)
            guard methods.contains(shape.key), isPath(after: position, in: live, of: draft) else { continue }
            draft.replace(
                at: index, with: shape.replacingCore(with: shape.core.uppercased()), by: .acronymCasing)
        }
        for (index, written) in reasonWords(in: draft) {
            draft.replace(at: index, with: written, by: .acronymCasing)
        }
    }

    /// Each word of a reason phrase straight after its code, by index, as it is written.
    static func reasonWords(in draft: Draft) -> [Int: String] {
        let live = draft.presentIndices.filter { !draft.words[$0].isLayoutMark }
        var written: [Int: String] = [:]
        for (position, index) in live.enumerated() {
            guard let phrase = reasons[draft.shape(at: index).core], position + phrase.count < live.count
            else { continue }
            let words = ((position + 1)...(position + phrase.count)).map { draft.shape(at: live[$0]) }
            guard zip(words, phrase).allSatisfy({ $0.key == $1.lowercased() }) else { continue }
            for (offset, shape) in words.enumerated() {
                written[live[position + 1 + offset]] = shape.replacingCore(with: phrase[offset])
            }
        }
        return written
    }

    /// Whether the word after `position`, past one linking word, is a path or a web address.
    private static func isPath(after position: Int, in live: [Int], of draft: Draft) -> Bool {
        var next = position + 1
        guard next < live.count else { return false }
        if linkers.contains(draft.shape(at: live[next]).key) { next += 1 }
        guard next < live.count else { return false }
        let text = draft.words[live[next]].text.lowercased()
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return true }
        return text.hasPrefix("/") && text.dropFirst().contains(where: { $0.isLetter || $0.isNumber })
    }
}
