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

    /// Reads the home mark and the number said right after it at a command line, a directory-stack entry: "tilde one" is "~1".
    static func readStackEntry(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        guard expecting.contains(.paths), let home, draft.spells(home.words, at: position, in: live) else {
            return nil
        }
        let place = position + home.words.count
        guard let (value, used) = number(at: place, within: run, in: live, of: draft),
            draft.shape(at: live[place - 1]).suffix.isEmpty, draft.shape(at: live[place]).prefix.isEmpty
        else { return nil }
        let span = position..<(place + used)
        guard onlyEndsAreMarked(span, in: live, of: draft) else { return nil }
        let first = draft.shape(at: live[position])
        let last = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(length: span.count, text: first.prefix + home.text + String(value) + last.suffix)
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
        while end + 1 < run.upperBound, draft.shape(at: live[end - 1]).suffix.isEmpty,
            let next = nextSegment(at: end, within: run, in: live, of: draft)
        {
            text += "/" + next.text
            end += next.length
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
        // Three spoken dots after a root are a package pattern's wildcard segment.
        if position + 3 <= run.upperBound,
            (position..<(position + 3)).allSatisfy({ draft.shape(at: live[$0]).key == "dot" })
        {
            return SpokenAddress(length: 3, text: "...")
        }
        // Before a name a "dot" opens a hidden one, as "dot config" is ".config"; before a "slash" it is a root.
        let hidden =
            position + 1 < run.upperBound && draft.shape(at: live[position]).key == "dot"
            && !["dot", "slash"].contains(draft.shape(at: live[position + 1]).key)
        let start = position + (hidden ? 1 : 0)
        guard let name = segmentName(at: start, within: run, in: live, of: draft) else { return nil }
        // A single letter between slashes is a directory called "a", though "a" is a function word.
        let after = start + name.length
        let joined =
            (after < run.upperBound && draft.shape(at: live[after]).key == "slash")
            || (start > run.lowerBound && draft.shape(at: live[start - 1]).key == "slash")
        let isLetter = name.text.count == 1 && name.text.first?.isLetter == true
        guard FunctionWords.isContent(name.text) || (isLetter && joined),
            !markNames.contains(name.text.lowercased())
        else {
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
            // Digits said one by one are one number, as in a meeting id: "one two three four five" is 12345.
            if let digits = spokenDigits(from: place, within: run, in: live, of: draft), digits.used >= 2 {
                pieces.append(digits.text)
                place += digits.used
            } else if let (value, used) = number(at: place, within: run, in: live, of: draft) {
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
            guard place + 1 < run.upperBound, draft.shape(at: live[place]).key == "dot",
                !opensHiddenFolder(at: place, within: run, in: live, of: draft),
                !opensParentDirectory(at: place, within: run, in: live, of: draft)
            else { break }
            place += 1
        }
        guard !pieces.isEmpty else { return nil }
        return SpokenAddress(length: place - position, text: pieces.joined(separator: "."))
    }

    /// The segment after its "slash", or a listed hidden folder a "dot" opens, with the words it used: "home dot ssh slash config".
    private static func nextSegment(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        if opensHiddenFolder(at: place, within: run, in: live, of: draft) {
            return segment(at: place, within: run, in: live, of: draft)
        }
        guard draft.shape(at: live[place]).key == "slash" else { return nil }
        // A "colon" opening a segment names a route parameter: "slash colon id" is "/:id".
        let parameter =
            place + 2 < run.upperBound && draft.shape(at: live[place + 1]).key == "colon"
            && draft.shape(at: live[place + 1]).suffix.isEmpty
        let start = place + 1 + (parameter ? 1 : 0)
        // Two spoken dots between slashes name the parent directory again: "dot dot slash dot dot slash build".
        if !parameter, opensParentDirectory(at: start, within: run, in: live, of: draft) {
            return SpokenAddress(length: start - place + 2, text: "..")
        }
        guard let next = segment(at: start, within: run, in: live, of: draft) else { return nil }
        return SpokenAddress(length: start - place + next.length, text: (parameter ? ":" : "") + next.text)
    }

    /// Whether two spoken dots and a "slash" start here, a parent directory a command word must not take a dot from.
    private static func opensParentDirectory(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> Bool {
        place + 2 < run.upperBound
            && (place..<(place + 2)).allSatisfy { draft.shape(at: live[$0]).key == "dot" }
            && draft.shape(at: live[place + 2]).key == "slash"
    }

    /// Whether a "dot" opens a hidden folder the lexicon lists that a "slash" follows, rather than joining two labels.
    private static func opensHiddenFolder(
        at place: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> Bool {
        guard place + 2 < run.upperBound, draft.shape(at: live[place]).key == "dot" else { return false }
        let (name, used) = label(at: place + 1, within: run, in: live, of: draft)
        let after = place + 1 + used
        return after < run.upperBound && hiddenFolders.contains(name.lowercased())
            && draft.shape(at: live[place + used]).suffix.isEmpty
            && draft.shape(at: live[after]).key == "slash"
    }

    /// Reads a slash-led path whose segments are words, bare of the marks its ends stood with, which the caller writes once.
    static func readPath(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard position < run.upperBound, draft.shape(at: live[position]).key == "slash" else { return nil }
        var end = position
        var text = ""
        while end + 1 < run.upperBound, let segment = nextSegment(at: end, within: run, in: live, of: draft) {
            text += "/" + segment.text
            end += segment.length
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
