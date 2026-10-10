// Keeps a sign-off from being signed with a name the person never wrote.

import Foundation

/// A closing such as "Kind regards," and the signature a completion may hang after it.
enum SignOff {
    /// Closings a signature follows, compared lowercased with the comma and outer spaces removed.
    static let closings: Set<String> = [
        "all the best", "best", "best regards", "best wishes", "cheers", "kind regards", "many thanks",
        "cordially", "love", "regards", "respectfully", "sincerely", "take care", "talk soon",
        "thank you", "thanks", "thanks again", "warm regards", "warmly", "with thanks", "yours",
        "yours sincerely", "yours truly",
    ]

    /// The line cut back to its closing unless the name after it is one the person wrote, or nothing when that leaves no continuation.
    static func unsigned(_ line: String, typed: String, ownLines: [String]) -> String? {
        guard let comma = closingComma(in: line) else { return line }
        let signature = words(of: String(line[line.index(after: comma)...]))
        // A signature is one to three capitalised words; lowercase words after it cannot make it safe.
        guard let first = signature.first, first.first?.isUppercase == true else { return line }
        let capitalised = Array(signature.prefix(while: { $0.first?.isUppercase == true }))
        let afterClosing = String(line[line.index(after: comma)...])
        // A long capitalised phrase is ordinary prose only when it has no title or comma continuation.
        if capitalised.count > longestSignature, first != "Dr",
            capitalised.count == signature.count, !afterClosing.contains(",")
        {
            return line
        }
        let name = Array(capitalised.prefix(longestSignature))
        let own = Set(ownLines.flatMap(words(of:)).filter { $0.first?.isUppercase == true })
        let typedName: Set<String> =
            closingComma(in: typed).map { comma in
                Set(
                    words(of: String(typed[typed.index(after: comma)...])).filter {
                        $0.first?.isUppercase == true
                    })
            } ?? []
        // A lowercase verb such as "will" does not establish "Will" as the person's name.
        guard name.allSatisfy({ own.contains($0) || typedName.contains($0) }) else {
            let closing = String(line[...comma])
            return closing.count > typed.count ? closing : nil
        }
        return line
    }

    /// Finds a closing that starts a line, or one mid-line followed by nothing or a bare signature.
    private static func closingComma(in line: String) -> String.Index? {
        for comma in line.indices where line[comma] == "," {
            let beforeComma = line[..<comma]
            let segmentStart =
                beforeComma.lastIndex(where: { ",.!?".contains($0) || $0.isNewline })
                .map { beforeComma.index(after: $0) } ?? line.startIndex
            let segment = beforeComma[segmentStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard closings.contains(segment) else { continue }
            let startsLine =
                segmentStart == line.startIndex || line[line.index(before: segmentStart)].isNewline
            guard startsLine || endsInBareSignature(after: comma, in: line) else { continue }
            return comma
        }
        return nil
    }

    /// Whether a mid-line closing ends the message or hangs only a capitalised name of up to three words.
    private static func endsInBareSignature(after comma: String.Index, in line: String) -> Bool {
        let following = String(line[line.index(after: comma)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return following.isEmpty || isBareSignature(following)
    }

    /// Whether a text is one to three capitalised words and nothing else.
    private static func isBareSignature(_ text: String) -> Bool {
        let signature = words(of: text)
        return !signature.isEmpty && signature.count <= longestSignature
            && signature.allSatisfy { $0.first?.isUppercase == true }
    }

    /// The most words a signature after a closing runs to.
    static let longestSignature = 3

    /// The words of a text, with the punctuation around them dropped.
    private static func words(of text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" }.map(String.init)
    }
}
