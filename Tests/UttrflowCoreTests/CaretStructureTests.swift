import Testing
import UttrflowTestSupport

@testable import UttrflowCore

@Suite("CaretStructure")
struct CaretStructureTests {
    static let seeds = Seeded.seeds(1...5)
    static let textsPerSeed = 2_000
    static let pieces = [
        "(", ")", "[", "]", "{", "}", "\"", "'", "\\", "a", "b", " ", "\n", "\r\n",
        "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}", "\u{00AB}", "\u{00BB}",
    ]

    static func texts(seed: Int) -> [String] {
        var random = Seeded(seed: seed)
        return (0..<textsPerSeed).map { _ in
            (0..<Int.random(in: 0...24, using: &random)).map { _ in random.pick(pieces) }.joined()
        }
    }

    @Test("open delimiters agree with the full-text scan the closer pass used", arguments: seeds)
    func openDelimiterMatchesFormerScan(seed: Int) {
        for text in Self.texts(seed: seed) {
            #expect(
                CaretStructure(precedingText: text).hasOpenDelimiter
                    == Former.hasUnclosedOpeningDelimiter(text),
                "seed=\(seed) \(text.debugDescription)")
        }
    }

    @Test("a bracket open on the caret line agrees with the line scan the stop pass used", arguments: seeds)
    func caretLineBracketMatchesFormerScan(seed: Int) {
        for text in Self.texts(seed: seed) {
            #expect(
                CaretStructure(precedingText: text).hasOpenBracketOnCaretLine
                    == Former.hasUnclosedBracketOnLastLine(text),
                "seed=\(seed) \(text.debugDescription)")
        }
    }

    @Test("a bracket opened on an earlier line is open but not on the caret line")
    func earlierLineBracket() {
        let structure = CaretStructure(precedingText: "call(\n  first")
        #expect(structure.hasOpenDelimiter)
        #expect(!structure.hasOpenBracketOnCaretLine)
        #expect(structure.caretLine == "  first")
        #expect(structure.openBrackets == [.init(opener: "(", isOnCaretLine: false)])
    }

    @Test("the caret line treats a CRLF pair as one break")
    func crlfCaretLine() {
        #expect(CaretStructure.caretLine(of: "one\r\ntwo") == "two")
        #expect(CaretStructure.caretLine(of: "one\n") == "")
        #expect(InsertionPoint(precedingText: "x").structure?.caretLine == "x")
        #expect(InsertionPoint.unknown.structure == nil)
    }

    @Test("the caret line's start is found by one walk, which a read limit cuts short")
    func lineStartWithLimit() {
        let text = "first\r\nsecond line"
        let start = CaretStructure.lineStart(in: text, before: text.endIndex)
        #expect(text[start.index...] == "second line")
        #expect(!start.isCut)
        let cut = CaretStructure.lineStart(in: text, before: text.endIndex, limit: 4)
        #expect(text[cut.index...] == "line")
        #expect(cut.isCut)
        let exact = CaretStructure.lineStart(in: "abcd", before: "abcd".endIndex, limit: 4)
        #expect(exact.index == "abcd".startIndex)
        #expect(!exact.isCut)
        for text in ["", "\n", "a\nb\n", "one\u{2028}two", "x\r\n"] {
            let split = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
            #expect(CaretStructure.caretLine(of: text) == split)
        }
    }
}

/// The two scans `CaretStructure` replaced, kept here only as the oracle the property tests compare against.
private enum Former {
    static func hasUnclosedOpeningDelimiter(_ text: String) -> Bool {
        var brackets: [Character] = []
        var double = false
        var single = false
        var curlyDouble = false
        var curlySingle = false
        var guillemet = false
        let characters = Array(text)
        var backslashes = 0
        for (offset, character) in characters.enumerated() {
            let previous = offset > 0 ? characters[offset - 1] : nil
            let next = offset + 1 < characters.count ? characters[offset + 1] : nil
            let inWord = previous?.isLetter == true && next?.isLetter == true
            switch character {
            case "(": brackets.append(")")
            case "[": brackets.append("]")
            case "{": brackets.append("}")
            case ")", "]", "}": if brackets.last == character { brackets.removeLast() }
            case "\"" where backslashes.isMultiple(of: 2): double.toggle()
            case "'" where backslashes.isMultiple(of: 2): if !inWord { single.toggle() }
            case "\u{201C}": curlyDouble = true
            case "\u{201D}": curlyDouble = false
            case "\u{2018}": curlySingle = true
            case "\u{2019}": if !inWord { curlySingle = false }
            case "\u{00AB}": guillemet = true
            case "\u{00BB}": guillemet = false
            default: break
            }
            backslashes = character == "\\" ? backslashes + 1 : 0
        }
        return !brackets.isEmpty || double || single || curlyDouble || curlySingle || guillemet
    }

    static func hasUnclosedBracketOnLastLine(_ text: String) -> Bool {
        let line = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
        var open: [Character] = []
        let closingFor: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        for character in line {
            if "([{".contains(character) {
                open.append(character)
            } else if let expected = closingFor[character], open.last == expected {
                open.removeLast()
            }
        }
        return !open.isEmpty
    }
}
