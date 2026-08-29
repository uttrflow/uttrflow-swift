import Foundation

/// Makes a clip's indentation consistent, and refuses whenever consistency cannot be
/// reached without guessing.
///
/// The claim this feature rests on is that whitespace-only normalisation cannot change
/// what the code means. That claim is true only if two things hold, and both of them are
/// this file's job to enforce rather than assume.
///
/// The first is that nothing but leading whitespace is ever touched. Every line here is
/// rebuilt as `newIndent + oldBody`, where `oldBody` is the original ``Substring``, so a
/// dropped line, an edited string literal or a normalised number is not a bug that could
/// happen — it is not expressible. Line count, trailing whitespace, the final newline and
/// its absence, `\r` line endings and blank lines all survive for the same reason.
///
/// The second is harder: leading whitespace is not always indentation. Inside a Swift
/// `"""` block or a Python `'''` block it is the text the program prints, and a tab at the
/// front of a makefile recipe is the syntax that makes it a recipe. Neither can be fixed
/// by being more careful about the rewrite, because the rewrite is not the problem —
/// knowing which lines are code is. So this type spends most of its length deciding
/// whether it understands the clip, and answers `nil` the moment it does not.
///
/// `nil` costs the user nothing: the panel simply does not offer the action. A wrong
/// answer costs them a corrupted paste they may not read before it reaches production.
/// Every threshold below is set on that asymmetry.
public enum CodeReindent {
    /// The clip with one indentation style throughout, or `nil` to leave it alone.
    ///
    /// - Parameter text: Exactly what was copied, untrimmed.
    /// - Returns: The re-indented text, or `nil` when the clip is already consistent,
    ///   when there is no indentation to normalise, or — the case that matters — when the
    ///   clip cannot be read confidently enough to be worth the risk.
    public static func reindented(_ text: String) -> String? {
        // Splitting on "\n" alone, so that a "\r\n" clip keeps its carriage returns as
        // ordinary trailing content that nothing here looks at or removes.
        let lines = text.components(separatedBy: "\n")

        // One line has no indentation relationship to anything, so there is nothing to
        // make consistent. This is also where the empty clip lands.
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

        // Tabs win only outright. A tie goes to spaces because that is the smaller edit:
        // with spaces as the target, every already-space-indented line comes out
        // byte-identical, since its width is a multiple of the unit by construction.
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

    /// What the whitespace at the front of a line turned out to be.
    private enum Indent {
        /// The line is whitespace and nothing else. Left exactly as found: its whitespace
        /// is as much trailing as leading, and this type does not touch trailing
        /// whitespace in any line.
        case blank
        /// The line starts at column zero.
        case flush
        case tabs(Int)
        case spaces(Int)

        /// - Returns: `nil` when the line's indentation mixes tabs and spaces, which has
        ///   no honest reading: relating the two needs a tab width, and a clip that is
        ///   already inconsistent is the last place to find a reliable one.
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

        /// The width of this line's space indent, for the lines that have one. Only these
        /// can measure the unit, so tabs contribute nothing to detecting it.
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

        /// How many levels deep this line sits, or `nil` for a blank line, which has no
        /// depth and is left alone.
        ///
        /// One tab is one level. That is an assumption, and the one this file cannot
        /// avoid making — but it is checked afterwards by ``climbsOneLevelAtATime(_:)``,
        /// which is where a clip whose tabs meant something else gets refused.
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

    /// The clip's own indentation unit, so that two-space code stays two-space.
    ///
    /// The smallest space indent present is the unit, because the first level of
    /// indentation is one unit by definition. Requiring every other width to be a
    /// multiple of it is what turns that from an assumption into a measurement: widths of
    /// 2, 4 and 6 agree on 2, while widths of 4 and 6 agree on nothing and are refused.
    ///
    /// - Returns: `nil` when no space-indented line exists to measure — an all-tab clip is
    ///   already consistent, so there is nothing to do — or when the smallest width is one
    ///   space, which no language uses as a level and which would make every other width a
    ///   multiple of it and so wave anything through, or when it is wider than eight,
    ///   which is past the widest indent anybody sets.
    private static func detectedUnit(from widths: [Int]) -> Int? {
        guard let smallest = widths.min(), (2...8).contains(smallest) else { return nil }
        guard widths.allSatisfy({ $0.isMultiple(of: smallest) }) else { return nil }
        return smallest
    }

    /// Whether the depths we read look like indentation at all.
    ///
    /// Code goes one level deeper at a time; it can come back out by several at once, but
    /// it cannot enter three blocks on one line. So a jump of more than one level says the
    /// unit or the tab width we assumed is wrong — the usual cause being a clip whose tabs
    /// stood for four columns while its spaces counted in twos, which would move a
    /// tab-indented line and a space-indented line that were level with each other onto
    /// different levels. In a brace language that is ugly; in Python it changes which
    /// block a statement is in. Either way we do not know enough, so we stop.
    ///
    /// The first non-blank line seeds the comparison rather than being measured against
    /// column zero, because clips are usually cut from the middle of a file and start
    /// already indented.
    private static func climbsOneLevelAtATime(_ levels: [Int?]) -> Bool {
        var previous: Int?
        for case .some(let level) in levels {
            if let previous, level > previous + 1 { return false }
            previous = level
        }
        return true
    }

    // MARK: - The clips we will not touch

    /// Whether any leading whitespace in this clip might be content rather than layout.
    ///
    /// Every test here is deliberately blunter than the language it is aimed at, because
    /// the alternative to bluntness is parsing, and a parser that is wrong once is worse
    /// than a rule that refuses ten harmless clips. A refused clip costs one menu item
    /// that was never shown.
    private static func mightHoldLiteralWhitespace(_ lines: [String]) -> Bool {
        for line in lines {
            // Swift, Python, Scala, Kotlin and Groovy all spell a multi-line string with
            // one of these two, and inside one the indentation is what the program prints.
            if line.contains("\"\"\"") || line.contains("'''") { return true }

            // A backtick opens a JavaScript template literal, which may span lines; it
            // also fences a markdown code block and opens a shell substitution. Only the
            // first is dangerous, and telling the three apart means pairing backticks
            // across the whole clip, which is the parsing we are refusing to do.
            if line.contains("`") { return true }

            // A heredoc body is verbatim text. No space is allowed between `<<` and the
            // tag, which is how every heredoc is actually written, and which is what keeps
            // C++'s `cout << x` and Ruby's `list << item` out of this.
            if line.firstMatch(of: heredocOpener) != nil { return true }

            // A line that opens a double-quoted string and does not close it is a string
            // that continues onto the next line — C#'s `@"..."`, a backslash continuation
            // inside a literal, or simply a language we have not thought of. We cannot see
            // where it ends, so we do not touch the clip.
            if !unescapedQuoteCount(line).isMultiple(of: 2) { return true }
        }
        return false
    }

    nonisolated(unsafe) private static let heredocOpener = #/<<[-~]?['"]?[A-Za-z_][A-Za-z0-9_]*/#

    /// Double quotes that actually open or close something, with `\"` discounted.
    ///
    /// Without discounting escapes, `print("a \" b")` counts three quotes and every clip
    /// containing one would be refused, which is enough false refusals to make the feature
    /// feel broken rather than careful.
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

    /// Whether this is a makefile, where the leading tab is not layout but grammar.
    ///
    /// A recipe line is a recipe line *because* it begins with a tab; turn those tabs into
    /// spaces and the rules stop having bodies, and turn a space-indented line into a
    /// tab-indented one and it becomes a command make will try to run. This is the one
    /// counterexample to "whitespace-only cannot change meaning", and no level-preserving
    /// rewrite can work around it, so makefiles are refused outright.
    ///
    /// The shape looked for is a tab-indented line directly beneath a rule at column zero.
    /// It also catches `def f():` with a tab-indented body, and that refusal is welcome:
    /// tab-and-space Python is exactly the clip where getting a level wrong moves a
    /// statement into a different block.
    private static func looksLikeMakefile(_ lines: [String]) -> Bool {
        var previous: String?
        for line in lines {
            defer { previous = line }
            guard line.hasPrefix("\t"), let target = previous else { continue }
            if target.wholeMatch(of: ruleHeader) != nil { return true }
        }
        return false
    }

    /// A rule at column zero: names, then a colon that is not `:=`, then the rest of the
    /// line. Anchored at the start with no leading whitespace allowed, because a target is
    /// always flush left and an indented `case x:` is not one.
    nonisolated(unsafe) private static let ruleHeader =
        #/[^\s:#=]+(?:[ \t]+[^\s:#=]+)*[ \t]*:(?:[^=\r].*)?\r?/#
}

extension Character {
    /// The only two characters this file will read as indentation, or write as it.
    ///
    /// Everything else that `isWhitespace` covers — a non-breaking space, a form feed — is
    /// treated as content, because a clip that carries one at the front of a line put it
    /// there on purpose more often than by accident.
    fileprivate var isIndentCharacter: Bool { self == " " || self == "\t" }
}
