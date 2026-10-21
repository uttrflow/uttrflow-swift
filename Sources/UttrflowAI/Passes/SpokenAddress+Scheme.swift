import UttrflowCore

extension SpokenAddress {
    /// Reads a spoken scheme, any user before "at", and its host: a host the words show is one is read anywhere, a bare name only at a command line.
    static func readExplicitURL(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft, expecting: Expectation
    ) -> SpokenAddress? {
        let (scheme, used) = label(at: position, within: run, in: live, of: draft)
        let separator = position + used
        guard isScheme(scheme), separator + 3 < run.upperBound,
            draft.shape(at: live[separator]).key == "colon",
            draft.shape(at: live[separator + 1]).key == "slash",
            draft.shape(at: live[separator + 2]).key == "slash"
        else { return nil }
        let user = userInfo(at: separator + 3, within: run, in: live, of: draft)
        let hostStart = separator + 3 + (user?.used ?? 0)
        // "s3 colon slash slash bucket" names a bucket at a command line; in prose a bare name after the slashes stays words.
        guard
            let host = readWebAddress(at: hostStart, within: run, in: live, of: draft)
                ?? readNumericHost(at: hostStart, within: run, in: live, of: draft)
                ?? readLocalhost(at: hostStart, within: run, in: live, of: draft)
                ?? (expecting.contains(.paths)
                    ? readBareHost(at: hostStart, within: run, in: live, of: draft) : nil)
        else {
            return nil
        }
        let end = hostStart + host.length
        let first = draft.shape(at: live[position])
        return SpokenAddress(
            length: end - position,
            text: first.prefix + scheme.lowercased() + "://" + (user?.text ?? "") + host.text)
    }

    /// The user said before the "at" that opens a URL's host, and the words it used: "app at" is "app@".
    private static func userInfo(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> (text: String, used: Int)? {
        guard let user = part(from: position, within: run, in: live, of: draft, side: .local),
            user.labels.count == 1
        else { return nil }
        let joint = position + user.length
        guard joint + 1 < run.upperBound, draft.shape(at: live[joint]).key == "at",
            onlyEndsAreMarked(position..<(joint + 1), in: live, of: draft)
        else { return nil }
        return (user.spelled + "@", joint + 1 - position)
    }

    /// Whether a word can name a URL scheme: a letter, then letters, digits, plus, dot or hyphen, and no function word.
    private static func isScheme(_ word: String) -> Bool {
        guard let first = word.first, first.isLetter, isLabel(word) else { return false }
        return FunctionWords.isContent(word.lowercased()) && !NumberWords.isNumber(word.lowercased())
    }

    /// Reads a host with no known ending that a spoken scheme has already shown to be one: "bucket", "my dash bucket".
    private static func readBareHost(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard let host = part(from: position, within: run, in: live, of: draft), host.hasLetter else {
            return nil
        }
        return finishHost(
            host.spelled, from: position, hostEnd: position + host.length, within: run, in: live, of: draft)
    }

    /// Reads a bare "localhost" that a spoken scheme has already shown to be a host.
    private static func readLocalhost(
        at position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> SpokenAddress? {
        guard position < run.upperBound, draft.shape(at: live[position]).key == "localhost" else {
            return nil
        }
        return finishHost(
            "localhost", from: position, hostEnd: position + 1, within: run, in: live, of: draft)
    }
}
