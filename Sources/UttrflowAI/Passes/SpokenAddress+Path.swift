import UttrflowCore

extension SpokenAddress {
    /// The mark and spoken name of a home directory, from the notation table, which can open a path.
    static let home = SpokenCommands.codeSymbols.first { $0.text == "~" }

    /// Reads a path with no host: two or more segments say a path on their own, one needs "path is" or a command line.
    static func readAbsolutePath(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        let root = root(at: position, within: run, in: live, of: draft)
        guard let path = readPath(at: position + root.used, within: run, in: live, of: draft) else {
            return nil
        }
        // A root names a directory of its own, so "~/notes" holds two segments as "/users/notes" does.
        let segments = path.text.filter { $0 == "/" }.count + (root.used > 0 ? 1 : 0)
        let announced =
            expecting.contains(.paths)
            || position > 1 && draft.shape(at: live[position - 1]).key == "is"
                && draft.shape(at: live[position - 2]).key == "path"
        guard segments > 1 || announced else { return nil }
        // A determiner before the first "slash" makes it a noun: "a slash or two".
        if position > 0, MentionGuard.phraseOpeners.contains(draft.shape(at: live[position - 1]).key) {
            return nil
        }
        let length = root.used + path.length
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[position + length - 1])
        return SpokenAddress(length: length, text: first.prefix + root.text + path.text + last.suffix)
    }

    /// The root said before a path's first "slash", the home mark or one or two dots, and how many words it used.
    private static func root(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (text: String, used: Int) {
        if let home, draft.spells(home.words, at: position, in: live) { return (home.text, home.words.count) }
        let dots = (position..<min(position + 2, run.upperBound))
            .prefix { draft.shape(at: live[$0]).key == "dot" }
        return (String(repeating: ".", count: dots.count), dots.count)
    }

    /// Reads labels joined by "slash", written only where a file ending closes the run or a path word announces it.
    static func readRelativePath(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        guard let head = segment(at: position, within: run, in: live, of: draft) else { return nil }
        var end = position + head.length
        var text = head.text
        while end + 1 < run.upperBound, draft.shape(at: live[end]).key == "slash",
            draft.shape(at: live[end - 1]).suffix.isEmpty,
            let next = segment(at: end + 1, within: run, in: live, of: draft)
        {
            text += "/" + next.text
            end += 1 + next.length
        }
        guard text.contains("/"), onlyEndsAreMarked(position..<end, in: live, of: draft) else { return nil }
        let ending = text.split(separator: "/").last?.split(separator: ".").dropFirst().last?.lowercased()
        let before = (max(0, position - 3)..<position).map { draft.shape(at: live[$0]).key }
        // A command line's first word is its command, so only a later word opens a path no word announces.
        let announced =
            expecting.contains(.paths) && position > 0 || before.contains(where: pathIntroducers.contains)
        // An everyday-word ending needs the cue a file name needs: "edit src slash main dot swift".
        let closed =
            ending.map {
                fileExtensions.contains($0)
                    && (!TechnicalToken.wordLikeFileExtensions.contains($0)
                        || isFileCued(before: position, in: live, of: draft))
            } ?? false
        guard announced || closed else { return nil }
        let (reference, used) = readReference(at: end, within: run, in: live, of: draft)
        end += used
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[end - 1])
        return SpokenAddress(length: end - position, text: first.prefix + text + reference + last.suffix)
    }

    /// One-word names the notation table writes as marks, which name a mark rather than a path segment.
    private static let markNames = Set(
        (SpokenCommands.marks + SpokenCommands.codeSymbols + SpokenCommands.flags)
            .compactMap { $0.words.count == 1 ? $0.words[0] : nil })

    /// One path segment, hidden where a "dot" opens it; a function word or a mark's name names none: "slash the budget".
    private static func segment(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        // Before a name a "dot" opens a hidden one, as "dot config" is ".config"; before a "slash" it is a root.
        let hidden =
            position + 1 < run.upperBound && draft.shape(at: live[position]).key == "dot"
            && !["dot", "slash"].contains(draft.shape(at: live[position + 1]).key)
        let start = position + (hidden ? 1 : 0)
        guard let name = segmentName(at: start, within: run, in: live, of: draft) else { return nil }
        guard FunctionWords.isContent(name.text), !markNames.contains(name.text.lowercased()) else {
            return nil
        }
        return SpokenAddress(length: start - position + name.length, text: (hidden ? "." : "") + name.text)
    }

    /// A segment's name: labels or spoken numbers joined by "dot", a spoken joiner extending a label, "v" taking a number.
    private static func segmentName(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        var pieces: [String] = []
        var place = position
        while place < run.upperBound {
            if let (value, used) = number(at: place, within: run, in: live, of: draft) {
                pieces.append(String(value))
                place += used
            } else {
                let (word, used) = label(at: place, within: run, in: live, of: draft)
                guard
                    word.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                        isLabel(String($0))
                    })
                else { return nil }
                var piece = word
                place += used
                if word.lowercased() == "v",
                    let (value, used) = number(at: place, within: run, in: live, of: draft)
                {
                    piece += String(value)
                    place += used
                }
                while let (grown, used, _) = growth(
                    at: place, within: run, in: live, of: draft, side: .domain)
                {
                    piece += grown
                    place += used
                }
                pieces.append(piece)
            }
            guard place + 1 < run.upperBound, draft.shape(at: live[place]).key == "dot" else { break }
            place += 1
        }
        guard !pieces.isEmpty else { return nil }
        return SpokenAddress(length: place - position, text: pieces.joined(separator: "."))
    }

    /// Reads a slash-led path whose segments are words, bare of the marks its ends stood with, which the caller writes once.
    static func readPath(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard position < run.upperBound, draft.shape(at: live[position]).key == "slash" else { return nil }
        var end = position
        var text = ""
        while end + 1 < run.upperBound, draft.shape(at: live[end]).key == "slash",
            let segment = segment(at: end + 1, within: run, in: live, of: draft)
        {
            text += "/" + segment.text
            end += 1 + segment.length
        }
        guard end > position else { return nil }
        return SpokenAddress(length: end - position, text: text)
    }

    /// Reads a hidden file, a spoken "dot" before a name the lexicon writes as a file ending: ".env.example".
    static func readHiddenFile(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard draft.shape(at: live[position]).key == "dot",
            let name = segment(at: position, within: run, in: live, of: draft), name.text.hasPrefix("."),
            let first = name.text.dropFirst().split(separator: ".").first?.lowercased(),
            fileExtensions.contains(first)
        else { return nil }
        // A determiner or an everyday-word name makes it a mention, "the dot md files", unless a file word cues it.
        let mentioned =
            position > 0 && MentionGuard.phraseOpeners.contains(draft.shape(at: live[position - 1]).key)
            || TechnicalToken.wordLikeFileExtensions.contains(first)
        guard !mentioned || isFileCued(before: position, in: live, of: draft),
            onlyEndsAreMarked(position..<(position + name.length), in: live, of: draft)
        else { return nil }
        let last = draft.shape(at: live[position + name.length - 1])
        return SpokenAddress(
            length: name.length, text: draft.shape(at: live[position]).prefix + name.text + last.suffix)
    }
}
