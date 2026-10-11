import UttrflowCore

/// The text rules a surroundings read applies to each line, pure string in and string out.
public enum SurroundingsText {
    /// The copy of every line nearest the field (the last) wins, so the tail still ends on the newest message; the focused element's own text is dropped too.
    static func deduplicated(_ lines: [String], dropping duplicate: String?) -> [String] {
        var seen: Set<String> = []
        var kept: [String] = []
        for line in lines.reversed() {
            if let duplicate, !duplicate.isEmpty, line == duplicate { continue }
            guard seen.insert(line).inserted else { continue }
            kept.append(line)
        }
        return kept.reversed()
    }

    /// Whether the label already says this text in its own whole words, which is what makes a child a repeat.
    static func repeats(_ text: String, in label: String?) -> Bool {
        guard let label, !text.isEmpty else { return false }
        var start = label.startIndex
        while let end = label.index(start, offsetBy: text.count, limitedBy: label.endIndex) {
            defer { start = label.index(after: start) }
            guard label[start..<end] == text else { continue }
            let opens = start == label.startIndex || !joinsAWord(label[label.index(before: start)])
            let closes = end == label.endIndex || !joinsAWord(label[end])
            if opens, closes { return true }
        }
        return false
    }

    /// Whether a character is part of a word, so "Sam" is not read as repeated inside "Samantha".
    private static func joinsAWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// The text without surrounding whitespace, control and direction marks or timestamp parts, cut to the per-element cap, or nothing.
    static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let clean = stripped(Substring(Timestamps.without(cleaned(text))))
        guard !clean.isEmpty else { return nil }
        return String(clean.suffix(Surroundings.maximumCharactersPerElement))
    }

    /// Whether an element's whole text is nothing but a stamp, the shape `trimmed` then empties out entirely.
    static func isClockOnly(_ text: String?) -> Bool {
        guard let text else { return false }
        let clock = stripped(Substring(cleaned(text)))
        return !clock.isEmpty && Timestamps.isTimestamp(clock)
    }

    /// The text without whitespace at either end.
    private static func stripped(_ text: Substring) -> Substring {
        var clean = text
        while let first = clean.first, first.isWhitespace { clean.removeFirst() }
        while let last = clean.last, last.isWhitespace { clean.removeLast() }
        return clean
    }

    /// The text without control and direction marks, each run of line breaks and tabs kept as one space between words.
    public static func cleaned(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        var separated = false
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control where scalar.properties.isWhitespace:
                if !separated { kept.append(" ") }
                separated = true
            case .format where scalar.value == 0x200C || scalar.value == 0x200D:
                kept.append(scalar)  // joiners change what the text is, so they stay
                separated = false
            case .control, .format:
                continue
            default:
                kept.append(scalar)
                separated = false
            }
        }
        return String(kept)
    }
}
