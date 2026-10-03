import UttrflowCore

/// An email address said aloud — a local part, "at", and a domain — and the address its words spell. See `Docs/cleanup.md`.
struct SpokenAddress: Equatable {
    /// How many live positions the address's words span.
    let length: Int
    /// The address as it is written, carrying the marks its first and last word stood with.
    let text: String

    /// The endings that make a spoken domain a domain; an unknown one is left as words rather than guessed at.
    static let topLevels = TechnicalToken.topLevels

    /// The words that announce an address, after which a local part spelled as a plain word is a mailbox.
    static let introducers: Set<String> = [
        "email", "emails", "emailed", "mail", "mails", "mailed", "address", "addresses",
        "send", "sends", "sent", "sending", "forward", "forwards", "forwarded",
        "copy", "copies", "copied", "cc", "write", "writes", "wrote", "contact", "reach", "invite",
    ]

    /// How many content words back an announcing word may stand from a local part spelled as a plain word.
    static let introducerReach = 2

    /// File endings that are common enough to write when a filename is announced.
    static let fileExtensions = TechnicalToken.fileExtensions

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

        /// The labels written as one, a dot wherever a spoken or a heard one stood between them.
        var spelled: String { labels.joined(separator: ".") }

        /// Whether the words say for themselves that they are an address: more than one label, or a mark or digit inside one.
        var isShaped: Bool {
            labels.count > 1 || labels.contains { label in label.contains { !$0.isLetter } }
        }

        /// Whether the words hold a letter, which a local part has and a spoken amount does not.
        var hasLetter: Bool { labels.contains { $0.contains(where: \.isLetter) } }
    }

    /// The address spoken from `position`, or nil where the words are not one.
    static func read(at position: Int, in live: [Int], of draft: Draft) -> SpokenAddress? {
        let run = position..<draft.sentenceEnd(from: position, in: live)
        if let url = readExplicitURL(at: position, within: run, in: live, of: draft) { return url }
        if let address = readWebAddress(at: position, within: run, in: live, of: draft) { return address }
        if let path = readAbsolutePath(at: position, within: run, in: live, of: draft) { return path }
        if let identifier = readIdentifier(at: position, within: run, in: live, of: draft) {
            return identifier
        }
        if let file = readFileName(at: position, within: run, in: live, of: draft) { return file }
        guard let local = part(from: position, within: run, in: live, of: draft),
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
        return path
    }

    /// Reads an explicitly spoken web scheme and its host.
    private static func readExplicitURL(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard draft.shape(at: live[position]).key == "https", position + 4 < run.upperBound,
            draft.shape(at: live[position + 1]).key == "colon",
            draft.shape(at: live[position + 2]).key == "slash",
            draft.shape(at: live[position + 3]).key == "slash"
        else { return nil }
        guard let host = readWebAddress(at: position + 4, within: run, in: live, of: draft) else {
            return nil
        }
        let end = position + 4 + host.length
        let first = draft.shape(at: live[position])
        return SpokenAddress(length: end - position, text: first.prefix + "https://" + host.text)
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

    /// Reads a slash-led path whose segments are words.
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
        let last = draft.shape(at: live[end - 1])
        return SpokenAddress(length: end - position, text: text + last.suffix)
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
        guard let first = part(from: position, within: run, in: live, of: draft),
            first.labels.count == 1, first.hasLetter
        else { return nil }
        let next = position + first.length
        guard next < run.upperBound else { return nil }
        let mark = draft.shape(at: live[next]).key
        let isAtHandle =
            mark == "at" && position > 0
            && draft.shape(at: live[position - 1]).key == "is"
        guard (mark == "underscore" && next + 1 < run.upperBound) || isAtHandle else { return nil }
        let secondPosition = next + 1
        guard let second = part(from: secondPosition, within: run, in: live, of: draft), second.hasLetter
        else {
            return nil
        }
        if mark == "underscore" {
            guard second.labels.count == 1 else { return nil }
        } else {
            guard isAtHandle,
                isDomainLike(second) || !ordinaryAtWords.contains(first.spelled.lowercased())
            else { return nil }
        }
        let glue = mark == "at" ? "@" : "_"
        let text = first.spelled + glue + second.spelled
        let last = draft.shape(at: live[secondPosition + second.length - 1])
        return SpokenAddress(
            length: secondPosition + second.length - position,
            text: draft.shape(at: live[position]).prefix + text + last.suffix)
    }

    /// A dotted known domain is strong evidence that the words around "at" name an address.
    private static func isDomainLike(_ part: Part) -> Bool {
        part.labels.count > 1 && part.labels.last.map { topLevels.contains($0.lowercased()) } == true
    }

    /// The labels spoken from `position`, which stands inside `run`, a spoken or a heard dot carrying on to the next.
    private static func part(
        from position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> Part? {
        var labels: [String] = []
        var place = position
        while true {
            let spelled = draft.shape(at: live[place]).core
                .split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard spelled.allSatisfy(isLabel) else { return nil }
            labels += spelled
            // A spoken "dot" carries the part on into the word after it; anything else ends the part here.
            guard place + 2 < run.upperBound, draft.shape(at: live[place + 1]).key == "dot" else {
                return Part(length: place + 1 - position, labels: labels)
            }
            place += 2
        }
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
