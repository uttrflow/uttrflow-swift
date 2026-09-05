// Makes a clip's indentation consistent, or refuses.

import Foundation

/// Normalises a clip's indentation, or refuses rather than guess. See Docs/clipboard-reindent.md.
public enum CodeReindent {
    /// The clip with one indentation style throughout, or `nil` when consistent, unindented or unreadable.
    public static func reindented(_ text: String) -> String? {
        // Split on "\n" alone, so a "\r\n" clip keeps its carriage returns as trailing content.
        let lines = text.components(separatedBy: "\n")

        // One line has no indentation relationship to anything; the empty clip lands here too.
        guard lines.count > 1 else { return nil }
        guard !mightHoldLiteralWhitespace(lines) else { return nil }
        guard !looksLikeMakefile(lines) else { return nil }

        var indents: [Indent] = []
        indents.reserveCapacity(lines.count)
        for line in lines {
            guard let indent = Indent(of: line) else { return nil }
            indents.append(indent)
        }

        let spaceRuns = indents.compactMap(\.spaceWidth)
        guard let unit = detectedUnit(from: spaceRuns) else { return nil }

        let levels = indents.map { $0.level(unit: unit) }
        guard climbsOneLevelAtATime(levels) else { return nil }

        // Tabs win only outright; a tie goes to spaces, the smaller edit.
        let tabbedLines = indents.count(where: \.isTabbed)
        let target = tabbedLines > spaceRuns.count ? "\t" : String(repeating: " ", count: unit)

        let rebuilt = zip(lines, levels).map { line, level -> String in
            guard let level else { return line }
            let body = line.drop(while: \.isIndentCharacter)
            return String(repeating: target, count: level) + body
        }

        let result = rebuilt.joined(separator: "\n")
        return result == text ? nil : result
    }

    // MARK: - Reading one line's indentation

    /// What the whitespace at the front of a line is.
    private enum Indent {
        /// The line is whitespace and nothing else, left exactly as found.
        case blank
        /// The line starts at column zero.
        case flush
        case tabs(Int)
        case spaces(Int)

        /// `nil` when the line mixes tabs and spaces, which has no honest reading without a tab width.
        init?(of line: String) {
            let leading = line.prefix(while: \.isIndentCharacter)
            if line.dropFirst(leading.count).allSatisfy(\.isWhitespace) {
                self = .blank
            } else if leading.isEmpty {
                self = .flush
            } else if leading.allSatisfy({ $0 == "\t" }) {
                self = .tabs(leading.count)
            } else if leading.allSatisfy({ $0 == " " }) {
                self = .spaces(leading.count)
            } else {
                return nil
            }
        }

        /// The width of this line's space indent; only these lines can measure the unit.
        var spaceWidth: Int? {
            switch self {
            case .spaces(let width): width
            default: nil
            }
        }

        var isTabbed: Bool {
            switch self {
            case .tabs: true
            default: false
            }
        }

        /// How many levels deep this line sits, or `nil` for a blank line; one tab is one level.
        func level(unit: Int) -> Int? {
            switch self {
            case .blank: nil
            case .flush: 0
            case .tabs(let count): count
            case .spaces(let width): width / unit
            }
        }
    }

    // MARK: - Reading the clip as a whole

    /// The smallest space indent, which every other width must be a multiple of; `nil` outside 2...8.
    private static func detectedUnit(from widths: [Int]) -> Int? {
        guard let smallest = widths.min(), (2...8).contains(smallest) else { return nil }
        guard widths.allSatisfy({ $0.isMultiple(of: smallest) }) else { return nil }
        return smallest
    }

    /// Whether the depths climb one level at a time, as code does; a bigger jump means the unit is wrong.
    private static func climbsOneLevelAtATime(_ levels: [Int?]) -> Bool {
        var previous: Int?
        for case .some(let level) in levels {
            if let previous, level > previous + 1 { return false }
            previous = level
        }
        return true
    }

    // MARK: - The clips we will not touch

    /// Whether any leading whitespace might be content rather than layout; blunt on purpose.
    private static func mightHoldLiteralWhitespace(_ lines: [String]) -> Bool {
        for line in lines {
            // Multi-line strings in Swift, Python, Scala, Kotlin and Groovy, whose indentation is printed.
            if line.contains("\"\"\"") || line.contains("'''") { return true }

            // A backtick may open a JavaScript template literal, and pairing them across a clip is parsing.
            if line.contains("`") { return true }

            // A heredoc body is verbatim; no space between `<<` and the tag keeps `cout << x` out of this.
            if line.firstMatch(of: heredocOpener) != nil { return true }

            // A double-quoted string left open continues onto the next line, and its end is unknown.
            if !unescapedQuoteCount(line).isMultiple(of: 2) { return true }
        }
        return false
    }

    nonisolated(unsafe) private static let heredocOpener = #/<<[-~]?['"]?[A-Za-z_][A-Za-z0-9_]*/#

    /// Double quotes that open or close something, with `\"` discounted so `print("a \" b")` passes.
    private static func unescapedQuoteCount(_ line: String) -> Int {
        var count = 0
        var escaped = false
        for character in line {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                count += 1
            }
        }
        return count
    }

    /// Whether this is a makefile, where a leading tab is grammar; tab-bodied Python is refused with it.
    private static func looksLikeMakefile(_ lines: [String]) -> Bool {
        var previous: String?
        for line in lines {
            defer { previous = line }
            guard line.hasPrefix("\t"), let target = previous else { continue }
            if target.wholeMatch(of: ruleHeader) != nil { return true }
        }
        return false
    }

    /// A rule at column zero: names, a colon that is not `:=`, then the rest of the line.
    nonisolated(unsafe) private static let ruleHeader =
        #/[^\s:#=]+(?:[ \t]+[^\s:#=]+)*[ \t]*:(?:[^=\r].*)?\r?/#
}

extension Character {
    /// The only two characters read or written as indentation; every other whitespace is content.
    fileprivate var isIndentCharacter: Bool { self == " " || self == "\t" }
}
