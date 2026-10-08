import UttrflowCore

/// An email address said aloud — a local part, "at", and a domain — and the address its words spell. See `Docs/cleanup.md`.
struct SpokenAddress: Equatable {
    /// How many live positions the address's words span.
    let length: Int
    /// The address as it is written, carrying the marks its first and last word stood with.
    let text: String

    /// The endings that make a spoken domain a domain; an unknown one is left as words rather than guessed at.
    static let topLevels = TechnicalToken.topLevels

    /// The web schemes a spoken "colon slash slash" may follow.
    static let schemes: Set<String> = ["http", "https"]

    /// The words that announce an address or a handle, after which a local part spelled as a plain word is a mailbox.
    static let introducers: Set<String> = [
        "email", "emails", "emailed", "mail", "mails", "mailed", "address", "addresses", "handle",
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

    /// Words that announce a relative path or a branch name, after which a run of labels joined by "slash" is written as one.
    static let pathIntroducers: Set<String> = ["path", "folder", "directory", "branch", "file", "filename"]

    /// Whether a word announcing a file stands within three words before `position`.
    static func isFileCued(before position: Int, in live: [Int], of draft: Draft) -> Bool {
        (max(0, position - 3)..<position).contains { fileIntroducers.contains(draft.shape(at: live[$0]).key) }
    }

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

    /// What the field is known to hold, which stands in for the word that would announce it.
    struct Expectation: OptionSet {
        let rawValue: Int
        /// A recipient field, where a plain-word mailbox needs no announcing word.
        static let addresses = Expectation(rawValue: 1 << 0)
        /// A command line, where labels joined by "slash" are a path with no path word before them.
        static let paths = Expectation(rawValue: 1 << 1)
    }

    /// The address spoken from `position` to no further than `sentenceEnd`, or nil where the words are not one.
    static func read(
        at position: Int, before sentenceEnd: Int, in live: [Int], of draft: Draft,
        expecting: Expectation = []
    ) -> SpokenAddress? {
        // A determiner opens a noun phrase, so the symbol name after it is a word: "the dot com bubble".
        guard !MentionGuard.phraseOpeners.contains(draft.shape(at: live[position]).key) else { return nil }
        let run = position..<sentenceEnd
        if let url = readExplicitURL(at: position, within: run, in: live, of: draft) { return url }
        if let host = readNumericHost(at: position, within: run, in: live, of: draft) { return host }
        if let address = readWebAddress(at: position, within: run, in: live, of: draft) { return address }
        if let path = readAbsolutePath(at: position, within: run, in: live, of: draft, expecting: expecting) {
            return path
        }
        if let path = readRelativePath(at: position, within: run, in: live, of: draft, expecting: expecting) {
            return path
        }
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
            domain.labels.count > 1, let top = domain.labels.last, topLevels.contains(top.lowercased()),
            local.isShaped || expecting.contains(.addresses)
                || isIntroduced(before: position, in: live, of: draft)
        else { return nil }
        let span = position..<(joint + 1 + domain.length)
        guard onlyEndsAreMarked(span, in: live, of: draft) else { return nil }
        let first = draft.shape(at: live[span.lowerBound])
        let last = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(
            length: span.count,
            text: first.prefix + local.spelled + "@" + domain.spelled.lowercased() + last.suffix)
    }

    /// Reads an IPv4 address, four spoken numbers of at most 255 joined by "dot", and any port and path after it.
    private static func readNumericHost(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        var octets: [Int] = []
        var place = position
        while octets.count < 4 {
            if !octets.isEmpty {
                guard place < run.upperBound, draft.shape(at: live[place]).key == "dot" else { return nil }
                place += 1
            }
            guard let (value, used) = number(at: place, within: run, in: live, of: draft), used > 0,
                value <= 255
            else {
                return nil
            }
            octets.append(value)
            place += used
        }
        return finishHost(
            octets.map(String.init).joined(separator: "."), from: position, hostEnd: place, within: run,
            in: live, of: draft)
    }

    /// The host's port, path and query, read after `hostEnd`, written with the marks the first and last word stood with.
    private static func finishHost(
        _ host: String, from position: Int, hostEnd: Int, within run: Range<Int>, in live: [Int],
        of draft: Draft
    ) -> SpokenAddress {
        var end = hostEnd
        var text = host
        if let (port, used) = colonNumber(at: end, within: run, in: live, of: draft),
            (1...65_535).contains(port)
        {
            text += ":" + String(port)
            end += used
        }
        if let path = readPath(at: end, within: run, in: live, of: draft) {
            text += path.text
            end += path.length
        }
        if let query = readQuery(at: end, within: run, in: live, of: draft) {
            text += query.text
            end += query.length
        }
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[end - 1])
        return SpokenAddress(length: end - position, text: first.prefix + text + last.suffix)
    }

    /// A "colon" joined to the word before it and the spoken number after it, and how many words both used.
    private static func colonNumber(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (value: Int, used: Int)? {
        guard place > 0, place + 1 < run.upperBound, draft.shape(at: live[place - 1]).suffix.isEmpty,
            draft.shape(at: live[place]).key == "colon",
            let (value, used) = number(at: place + 1, within: run, in: live, of: draft)
        else { return nil }
        return (value, 1 + used)
    }

    /// A file's line and optional column said after it, written joined without grouping: "main.py:42:7".
    static func readReference(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (text: String, used: Int) {
        var text = ""
        var used = 0
        for _ in 0..<2 {
            guard let (value, step) = colonNumber(at: place + used, within: run, in: live, of: draft) else {
                break
            }
            text += ":" + String(value)
            used += step
        }
        return (text, used)
    }

    /// Reads a query said as "question mark", then name "equals" value pairs joined by "and" or "ampersand".
    private static func readQuery(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard position + 4 < run.upperBound, draft.shape(at: live[position]).key == "question",
            draft.shape(at: live[position + 1]).key == "mark"
        else { return nil }
        var place = position + 2
        var pairs: [String] = []
        while place + 2 < run.upperBound {
            let name = draft.shape(at: live[place]).core
            let value = draft.shape(at: live[place + 2]).core
            guard isLabel(name), draft.shape(at: live[place + 1]).key == "equals", isLabel(value) else {
                break
            }
            pairs.append(name + "=" + value)
            place += 3
            guard place + 3 < run.upperBound, ["and", "ampersand"].contains(draft.shape(at: live[place]).key)
            else { break }
            let next = draft.shape(at: live[place + 2]).key
            guard next == "equals" else { break }
            place += 1
        }
        guard !pairs.isEmpty else { return nil }
        return SpokenAddress(length: place - position, text: "?" + pairs.joined(separator: "&"))
    }

    /// A spoken or written whole number at `place` and how many words it used.
    static func number(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (value: Int, used: Int)? {
        guard place < run.upperBound else { return nil }
        let core = draft.shape(at: live[place]).core
        if !core.isEmpty, core.allSatisfy(\.isASCII), core.allSatisfy(\.isNumber) {
            return Int(core).map { ($0, 1) }
        }
        let keys = (place..<run.upperBound).lazy.map { draft.shape(at: live[$0]).key }
            .prefix { NumberWords.value(of: $0) != nil }
        return NumberWords.cardinal(ArraySlice(keys)).map { ($0.value, $0.count) }
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
        guard
            let host = readWebAddress(at: separator + 3, within: run, in: live, of: draft)
                ?? readNumericHost(at: separator + 3, within: run, in: live, of: draft)
        else {
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
        if draft.shape(at: live[position]).key == "www", position + 2 < run.upperBound,
            draft.shape(at: live[position + 1]).key == "dot"
        {
            hostPosition = position + 2
            prefix = "www."
        } else {
            hostPosition = position
            prefix = ""
        }
        if prefix.isEmpty, draft.shape(at: live[position]).key == "localhost" {
            let host = finishHost(
                "localhost", from: position, hostEnd: position + 1, within: run, in: live, of: draft)
            // A bare "localhost" is a word; only a port or path after it makes it a host.
            return host.length > 1 ? host : nil
        }
        guard let host = part(from: hostPosition, within: run, in: live, of: draft),
            host.labels.count > 1, let top = host.labels.last, topLevels.contains(top.lowercased())
        else { return nil }
        let address = finishHost(
            prefix + host.spelled.lowercased(), from: position, hostEnd: hostPosition + host.length,
            within: run,
            in: live, of: draft)
        // A bare name that a noun follows names a company, not a site: "at Example dot com offices".
        let after = position + address.length
        let isBare = prefix.isEmpty && after == hostPosition + host.length
        if isBare, after < run.upperBound, !draft.shape(at: live[after - 1]).endsClause,
            FunctionWords.isContent(draft.shape(at: live[after]).key)
        {
            return nil
        }
        return address
    }

    /// Reads a file name: an ending no one says as a word is enough, an everyday-word ending needs a cue.
    private static func readFileName(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        if let hidden = readHiddenFile(at: position, within: run, in: live, of: draft) { return hidden }
        // A spoken "dot" carries a part on, so the name and its ending arrive as one part's labels.
        guard let name = part(from: position, within: run, in: live, of: draft), name.labels.count > 1,
            name.hasLetter, FunctionWords.isContent(name.labels[0]),
            let ending = name.labels.last?.lowercased(),
            fileExtensions.contains(ending),
            !TechnicalToken.wordLikeFileExtensions.contains(ending)
                || isFileCued(before: position, in: live, of: draft)
        else { return nil }
        let (reference, used) = readReference(at: position + name.length, within: run, in: live, of: draft)
        let end = position + name.length + used
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[end - 1])
        return SpokenAddress(
            length: end - position, text: first.prefix + name.spelled + reference + last.suffix)
    }

    /// Reads identifiers and handles only when a local cue establishes their syntactic role.
    private static func readIdentifier(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        let opening = draft.shape(at: live[position])
        // "is at" before a name joined by a spoken underscore names a handle, written with "@".
        if opening.key == "at", opening.suffix.isEmpty, position > 0,
            draft.shape(at: live[position - 1]).key == "is",
            let handle = underscored(at: position + 1, within: run, in: live, of: draft)
        {
            return SpokenAddress(length: handle.length + 1, text: opening.prefix + "@" + handle.text)
        }
        if let name = underscored(at: position, within: run, in: live, of: draft) { return name }
        guard position > 0, draft.shape(at: live[position - 1]).key == "is",
            let first = part(from: position, within: run, in: live, of: draft),
            first.labels.count == 1, first.hasLetter
        else { return nil }
        let next = position + first.length
        guard next + 1 < run.upperBound, draft.shape(at: live[next]).key == "at" else { return nil }
        let secondPosition = next + 1
        // Without a domain, two plain words either side of "at" are prose; only an announcing word makes them a handle.
        guard let second = part(from: secondPosition, within: run, in: live, of: draft), second.hasLetter,
            isDomainLike(second)
                || (FunctionWords.isContent(first.spelled) && FunctionWords.isContent(second.spelled)
                    && !isBareNumber(second) && isIntroduced(before: position, in: live, of: draft))
        else { return nil }
        let text = first.spelled + "@" + second.spelled
        let last = draft.shape(at: live[secondPosition + second.length - 1])
        return SpokenAddress(
            length: secondPosition + second.length - position,
            text: draft.shape(at: live[position]).prefix + text + last.suffix)
    }

    /// A name joined by a spoken underscore, which names an identifier on its own; one followed by "at" is a local part, read as an address.
    private static func underscored(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard position < run.upperBound,
            let name = part(from: position, within: run, in: live, of: draft, side: .local),
            name.length > 1, name.labels.count == 1, name.labels[0].contains("_"), name.hasLetter
        else { return nil }
        let next = position + name.length
        guard next == run.upperBound || draft.shape(at: live[next]).key != "at" else { return nil }
        let last = draft.shape(at: live[next - 1])
        return SpokenAddress(
            length: name.length, text: draft.shape(at: live[position]).prefix + name.spelled + last.suffix)
    }

    /// A dotted known domain is strong evidence that the words around "at" name an address.
    private static func isDomainLike(_ part: Part) -> Bool {
        part.labels.count > 1 && part.labels.last.map { topLevels.contains($0.lowercased()) } == true
    }

    /// A single spoken or written number after "at" is a time or a quantity, never a handle's domain.
    private static func isBareNumber(_ part: Part) -> Bool {
        part.labels.count == 1 && NumberWords.isNumber(part.labels[0].lowercased())
    }

    /// The labels spoken from `position`, which stands inside `run`: a spoken or a heard dot carries on to the next label, and a spoken joiner or number extends the one being read.
    private static func part(
        from position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, side: Side = .domain
    ) -> Part? {
        // "www dot" can end a piece, so the host it announces may lie past the run.
        guard run.contains(position) else { return nil }
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
    static func growth(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft, side: Side
    ) -> (piece: String, used: Int, marks: Bool)? {
        guard place < run.upperBound, draft.shape(at: live[place - 1]).suffix.isEmpty else { return nil }
        let shape = draft.shape(at: live[place])
        guard shape.prefix.isEmpty else { return nil }
        if let joiner = joiners[shape.key], side == .local || joiner != "+", place + 1 < run.upperBound,
            shape.suffix.isEmpty
        {
            let next = draft.shape(at: live[place + 1])
            // A determiner after the joiner opens a noun phrase, so the joiner is a word: "results underscore the need".
            guard next.prefix.isEmpty, joiners[next.key] == nil, next.key != "dot", isLabel(next.core),
                !MentionGuard.phraseOpeners.contains(next.key)
            else {
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
    static func label(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (word: String, used: Int) {
        var end = place
        while end < run.upperBound, isSpelledLetter(draft.shape(at: live[end])),
            end == place
                || draft.shape(at: live[end - 1]).suffix.isEmpty && draft.shape(at: live[end]).prefix.isEmpty
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
    static func isLabel(_ label: String) -> Bool {
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
    static func onlyEndsAreMarked(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.allSatisfy { place in
            let shape = draft.shape(at: live[place])
            return (place == span.lowerBound || shape.prefix.isEmpty)
                && (place == span.upperBound - 1 || shape.suffix.isEmpty)
        }
    }
}
