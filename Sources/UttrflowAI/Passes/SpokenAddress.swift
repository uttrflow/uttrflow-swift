import UttrflowCore

/// An email address said aloud — a local part, "at", and a domain — and the address its words spell. See `Docs/cleanup.md`.
struct SpokenAddress: Equatable {
    /// How many live positions the address's words span.
    let length: Int
    /// The address as it is written, carrying the marks its first and last word stood with.
    let text: String

    /// The endings that make a spoken domain a domain; an unknown one is left as words rather than guessed at.
    static let topLevels: Set<String> = [
        "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz",
        "io", "co", "ai", "dev", "app", "me", "sh", "xyz", "tech", "online", "site", "store", "cloud",
        "in", "uk", "us", "ca", "au", "de", "fr", "nl", "es", "it", "jp", "cn", "br", "ru", "ie", "nz",
    ]

    /// The web schemes a spoken "colon slash slash" may follow.
    static let schemes: Set<String> = ["http", "https"]

    /// The words that announce an address, after which a local part spelled as a plain word is a mailbox.
    static let introducers: Set<String> = [
        "email", "emails", "emailed", "mail", "mails", "mailed", "address", "addresses",
        "send", "sends", "sent", "sending", "forward", "forwards", "forwarded",
        "copy", "copies", "copied", "cc", "write", "writes", "wrote", "contact", "reach", "invite",
    ]

    /// How many content words back an announcing word may stand from a local part spelled as a plain word.
    static let introducerReach = 2

    /// File endings that are common enough to write when a filename is announced.
    static let fileExtensions: Set<String> = [
        "json", "txt", "md", "swift", "py", "js", "ts", "html", "css", "xml", "csv", "pdf",
        "yaml", "yml", "toml", "sh", "rb", "go", "rs", "kt", "java", "png", "jpg", "zip",
    ]

    /// Words that announce a path or filename rather than a spoken ordinary noun.
    static let fileIntroducers: Set<String> = [
        "file", "filename", "path", "directory", "folder", "package", "open", "edit",
    ]

    /// Common words that can follow "is" in ordinary prose, never a spoken handle's local part.
    private static let ordinaryAtWords: Set<String> = [
        "just", "parked", "not", "out", "open", "right", "still", "the",
    ]

    /// One side of an address: how many live positions it spans and the labels its words spell.
    struct Part: Equatable {
        let length: Int
        let labels: [String]
        /// Whether the words say for themselves that they are an address: more than one label, a written mark or digit, or a spoken underscore.
        let isShaped: Bool

        /// The labels written as one, a dot wherever a spoken or a heard one stood between them.
        var spelled: String { labels.joined(separator: ".") }

        /// Whether the words hold a letter, which a local part has and a spoken amount does not.
        var hasLetter: Bool { labels.contains { $0.contains(where: \.isLetter) } }
    }

    /// Which side of "at" a part is read for: only a local part takes a plus tag or a number.
    enum Side { case local, domain }

    /// The spoken words that join two pieces of one label, and the mark each writes.
    static let joiners: [String: Character] = ["underscore": "_", "dash": "-", "hyphen": "-", "plus": "+"]

    /// The joiners a spoken joiner alone does not make an address of, because prose says them too.
    private static let proseJoiners: Set<Character> = ["-", "+"]

    /// The address spoken from `position` to no further than `sentenceEnd`, or nil where the words are not one.
    static func read(
        at position: Int, before sentenceEnd: Int, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        let run = position..<sentenceEnd
        if let url = readExplicitURL(at: position, within: run, in: live, of: draft) { return url }
        if let address = readWebAddress(at: position, within: run, in: live, of: draft) { return address }
        if let path = readAbsolutePath(at: position, within: run, in: live, of: draft) { return path }
        if let identifier = readIdentifier(at: position, within: run, in: live, of: draft) {
            return identifier
        }
        if let file = readFileName(at: position, within: run, in: live, of: draft) { return file }
        guard let local = part(from: position, within: run, in: live, of: draft, side: .local),
            local.hasLetter, FunctionWords.isContent(local.spelled)
        else { return nil }
        let joint = position + local.length
        guard joint + 1 < run.upperBound, draft.shape(at: live[joint]).key == "at",
            let domain = part(from: joint + 1, within: run, in: live, of: draft),
            domain.labels.count > 1, let top = domain.labels.last, topLevels.contains(top),
            local.isShaped || isIntroduced(before: position, in: live, of: draft)
        else { return nil }
        let span = position..<(joint + 1 + domain.length)
        guard onlyEndsAreMarked(span, in: live, of: draft) else { return nil }
        let first = draft.shape(at: live[span.lowerBound])
        let last = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(
            length: span.count, text: first.prefix + local.spelled + "@" + domain.spelled + last.suffix)
    }

    /// Reads an absolute path when the words announce a path immediately before it.
    private static func readAbsolutePath(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard position > 0, draft.shape(at: live[position]).key == "slash",
            draft.shape(at: live[position - 1]).key == "is",
            position > 1, draft.shape(at: live[position - 2]).key == "path",
            let path = readPath(at: position, within: run, in: live, of: draft)
        else { return nil }
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[position + path.length - 1])
        return SpokenAddress(length: path.length, text: first.prefix + path.text + last.suffix)
    }

    /// Reads an explicitly spoken web scheme and its host.
    private static func readExplicitURL(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        let (scheme, used) = label(at: position, within: run, in: live, of: draft)
        let separator = position + used
        guard schemes.contains(scheme.lowercased()), separator + 3 < run.upperBound,
            draft.shape(at: live[separator]).key == "colon",
            draft.shape(at: live[separator + 1]).key == "slash",
            draft.shape(at: live[separator + 2]).key == "slash"
        else { return nil }
        guard let host = readWebAddress(at: separator + 3, within: run, in: live, of: draft) else {
            return nil
        }
        let end = separator + 3 + host.length
        let first = draft.shape(at: live[position])
        return SpokenAddress(
            length: end - position, text: first.prefix + scheme.lowercased() + "://" + host.text)
    }

    /// Reads a known host and its spoken slash-separated path.
    private static func readWebAddress(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        let hostPosition: Int
        let prefix: String
        if draft.shape(at: live[position]).key == "www", position + 1 < run.upperBound,
            draft.shape(at: live[position + 1]).key == "dot"
        {
            hostPosition = position + 2
            prefix = "www."
        } else {
            hostPosition = position
            prefix = ""
        }
        guard let host = part(from: hostPosition, within: run, in: live, of: draft),
            host.labels.count > 1, let top = host.labels.last, topLevels.contains(top.lowercased())
        else { return nil }
        let precededByScheme = position >= 4 && draft.shape(at: live[position - 4]).key == "https"
        guard !prefix.isEmpty || host.labels.count > 1 || precededByScheme else { return nil }
        let hostText = prefix + host.spelled
        var end = hostPosition + host.length
        var text = hostText
        if let path = readPath(at: end, within: run, in: live, of: draft) {
            text += path.text
            end += path.length
        }
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[end - 1])
        return SpokenAddress(length: end - position, text: first.prefix + text + last.suffix)
    }

    /// Reads a slash-led path whose segments are words, bare of the marks its ends stood with, which the caller writes once.
    private static func readPath(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard position < run.upperBound, draft.shape(at: live[position]).key == "slash" else { return nil }
        var end = position
        var text = ""
        while end + 1 < run.upperBound, draft.shape(at: live[end]).key == "slash" {
            var segment = draft.shape(at: live[end + 1]).core
            guard isLabel(segment) else { break }
            var step = 2
            if end + 3 < run.upperBound, draft.shape(at: live[end + 2]).key == "v",
                let digit = spokenSmallNumber(draft.shape(at: live[end + 3]).key)
            {
                segment = "v" + digit
                step = 4
            }
            text += "/" + segment
            end += step
        }
        guard end > position else { return nil }
        return SpokenAddress(length: end - position, text: text)
    }

    /// Small number names that commonly follow a version prefix in a dictated path.
    private static func spokenSmallNumber(_ word: String) -> String? {
        ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"].firstIndex(of: word)
            .map(String.init)
    }

    /// Reads an announced file extension, including the special hidden filename `.env`.
    private static func readFileName(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        if draft.shape(at: live[position]).key == "dot", position + 1 < run.upperBound,
            draft.shape(at: live[position + 1]).key == "env", position > 0,
            draft.shape(at: live[position - 1]).key == "the", position > 1,
            ["edit", "open"].contains(draft.shape(at: live[position - 2]).key)
        {
            let first = draft.shape(at: live[position])
            let last = draft.shape(at: live[position + 1])
            return SpokenAddress(length: 2, text: first.prefix + ".env" + last.suffix)
        }
        guard let base = part(from: position, within: run, in: live, of: draft),
            base.labels.count == 1, base.hasLetter, position + base.length + 1 < run.upperBound
        else { return nil }
        let dot = position + base.length
        guard draft.shape(at: live[dot]).key == "dot",
            let ext = part(from: dot + 1, within: run, in: live, of: draft), ext.labels.count == 1,
            fileExtensions.contains(ext.labels[0].lowercased()),
            fileIntroducers.contains(where: { cue in
                let start = max(0, position - 3)
                return (start..<position).contains { draft.shape(at: live[$0]).key == cue }
            })
        else { return nil }
        let end = dot + 1 + ext.length
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[end - 1])
        return SpokenAddress(
            length: end - position, text: first.prefix + base.spelled + "." + ext.spelled + last.suffix)
    }

    /// Reads identifiers and handles only when a local cue establishes their syntactic role.
    private static func readIdentifier(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        if let name = part(from: position, within: run, in: live, of: draft, side: .local),
            name.length > 1, name.labels.count == 1, name.labels[0].contains("_"), name.hasLetter
        {
            let next = position + name.length
            // A spoken underscore names an identifier on its own; one followed by "at" is a local part, read as an address.
            guard next == run.upperBound || draft.shape(at: live[next]).key != "at" else { return nil }
            let last = draft.shape(at: live[next - 1])
            return SpokenAddress(
                length: name.length, text: draft.shape(at: live[position]).prefix + name.spelled + last.suffix
            )
        }
        guard position > 0, draft.shape(at: live[position - 1]).key == "is",
            let first = part(from: position, within: run, in: live, of: draft),
            first.labels.count == 1, first.hasLetter
        else { return nil }
        let next = position + first.length
        guard next + 1 < run.upperBound, draft.shape(at: live[next]).key == "at" else { return nil }
        let secondPosition = next + 1
        guard let second = part(from: secondPosition, within: run, in: live, of: draft), second.hasLetter,
            isDomainLike(second) || !ordinaryAtWords.contains(first.spelled.lowercased())
        else { return nil }
        let text = first.spelled + "@" + second.spelled
        let last = draft.shape(at: live[secondPosition + second.length - 1])
        return SpokenAddress(
            length: secondPosition + second.length - position,
            text: draft.shape(at: live[position]).prefix + text + last.suffix)
    }

    /// A dotted known domain is strong evidence that the words around "at" name an address.
    private static func isDomainLike(_ part: Part) -> Bool {
        part.labels.count > 1 && part.labels.last.map { topLevels.contains($0.lowercased()) } == true
    }

    /// The labels spoken from `position`, which stands inside `run`: a spoken or a heard dot carries on to the next label, and a spoken joiner or number extends the one being read.
    private static func part(
        from position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, side: Side = .domain
    ) -> Part? {
        var labels: [String] = []
        var shaped = false
        var place = position
        while true {
            let (word, used) = label(at: place, within: run, in: live, of: draft)
            let spelled = word.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard spelled.allSatisfy(isLabel) else { return nil }
            shaped = shaped || spelled.count > 1 || spelled.contains { $0.contains { !$0.isLetter } }
            labels += spelled
            place += used
            while let (piece, used, marks) = growth(at: place, within: run, in: live, of: draft, side: side) {
                labels[labels.count - 1] += piece
                shaped = shaped || marks
                place += used
            }
            // A spoken "dot" carries the part on into the word after it; anything else ends the part here.
            guard place + 1 < run.upperBound, draft.shape(at: live[place]).key == "dot" else {
                return Part(length: place - position, labels: labels, isShaped: shaped || labels.count > 1)
            }
            place += 1
        }
    }

    /// The piece a spoken joiner and its word, or a spoken number, add to the label before `place`, with how many words it used and whether it marks an address.
    private static func growth(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft, side: Side
    ) -> (piece: String, used: Int, marks: Bool)? {
        guard place < run.upperBound, draft.shape(at: live[place - 1]).suffix.isEmpty else { return nil }
        let shape = draft.shape(at: live[place])
        guard shape.prefix.isEmpty else { return nil }
        if let joiner = joiners[shape.key], side == .local || joiner != "+", place + 1 < run.upperBound,
            shape.suffix.isEmpty
        {
            let next = draft.shape(at: live[place + 1])
            guard next.prefix.isEmpty, joiners[next.key] == nil, next.key != "dot", isLabel(next.core) else {
                return nil
            }
            return (String(joiner) + next.core, 2, !proseJoiners.contains(joiner))
        }
        guard side == .local else { return nil }
        // A number is said in prose as often as in a mailbox, so it joins the label without being evidence for one.
        if shape.core.allSatisfy(\.isNumber), !shape.core.isEmpty { return (shape.core, 1, false) }
        let keys = (place..<run.upperBound).lazy.map { draft.shape(at: live[$0]).key }
            .prefix { NumberWords.value(of: $0) != nil }
        guard let number = NumberWords.cardinal(ArraySlice(keys)) else { return nil }
        return (String(number.value), number.count, false)
    }

    /// The word at `place` and how many words it spans: a run of two or more unmarked single letters is one spelled word.
    private static func label(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (word: String, used: Int) {
        var end = place
        while end < run.upperBound, isSpelledLetter(draft.shape(at: live[end])),
            end == place || draft.shape(at: live[end - 1]).suffix.isEmpty && draft.shape(at: live[end]).prefix.isEmpty
        {
            end += 1
        }
        guard end - place >= 2 else { return (draft.shape(at: live[place]).core, 1) }
        return ((place..<end).map { draft.shape(at: live[$0]).core.lowercased() }.joined(), end - place)
    }

    /// Whether a word is one letter said on its own, as a spelled word is said.
    private static func isSpelledLetter(_ shape: WordShape) -> Bool {
        shape.core.count == 1 && shape.core.allSatisfy(\.isLetter)
    }

    /// Whether a label can stand in an address: letters, digits, hyphens and underscores, and nothing else.
    private static func isLabel(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Whether an address is announced before a plain local part: an announcing word, or an address already written, within reach.
    private static func isIntroduced(before position: Int, in live: [Int], of draft: Draft) -> Bool {
        // A determiner in front makes the word the noun of a phrase — "send the report at example.com" — never a mailbox.
        if position > 0,
            MentionGuard.phraseOpeners.contains(draft.shape(at: live[position - 1]).key)
        {
            return false
        }
        var content = 0
        var place = position - 1
        while place >= 0, content < introducerReach {
            let shape = draft.shape(at: live[place])
            // A noun phrase cannot begin in the sentence before, which is how the mention guard reads a lookback too.
            guard !shape.endsSentence else { return false }
            if !FunctionWords.holds(shape.key) {
                if introducers.contains(shape.key) || shape.core.contains("@") { return true }
                content += 1
            }
            place -= 1
        }
        return false
    }

    /// Whether only the address's ends carry marks, a mark inside the words meaning they are not one address.
    private static func onlyEndsAreMarked(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.allSatisfy { place in
            let shape = draft.shape(at: live[place])
            return (place == span.lowerBound || shape.prefix.isEmpty)
                && (place == span.upperBound - 1 || shape.suffix.isEmpty)
        }
    }
}
