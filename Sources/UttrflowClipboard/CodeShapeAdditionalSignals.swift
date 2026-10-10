import Foundation
import UttrflowCore

extension CodeShapes {
    /// Error output is text to inspect, not source code to format.
    static func isDiagnosticOutput(_ text: String) -> Bool {
        text.hasPrefix("npm ERR!") || text.hasPrefix("Traceback (most recent call last):")
    }

    /// Markup whose opening and closing structure describes the whole clip.
    static func isMarkup(_ text: String) -> Bool {
        text.firstMatch(of: htmlDoctype) != nil || text.wholeMatch(of: pairedMarkup) != nil
            || text.wholeMatch(of: structuralHTMLTag) != nil
    }

    nonisolated(unsafe) static let htmlDoctype = #/(?i)^\h*<!doctype\h+html(?:\h[^>]*)?>/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let pairedMarkup = #/<([A-Za-z][\w:-]*)(?:\h[^<>]*)?>[\s\S]*</\1\h*>/#

    nonisolated(unsafe) static let structuralHTMLTag =
        #/(?i)^\h*<(?:html|head|body|div|ul|ol|li|img|form|input|button|table|article|section|meta|link|script|title)(?:\h[^<>]*)?/?>\h*$/#
        .anchorsMatchLineEndings()

    /// Markdown syntax that identifies the whole clip: a heading, a table, or a closed fence.
    static func isMarkdown(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        if lines.contains(where: { $0.wholeMatch(of: markdownHeading) != nil }) { return true }
        if zip(lines, lines.dropFirst()).contains(where: { isMarkdownTableHeader($0.0, followedBy: $0.1) }) {
            return true
        }
        guard let first = lines.first, let last = lines.last else { return false }
        return first.wholeMatch(of: markdownFenceOpen) != nil
            && last.wholeMatch(of: markdownFenceClose) != nil
            && lines.count >= 3
    }

    static func isMarkdownTableHeader(_ header: Substring, followedBy separator: Substring) -> Bool {
        header.contains("|") && separator.contains("|")
            && separator.filter { $0 == "-" }.count >= 3
            && separator.allSatisfy { "|:- \t".contains($0) }
    }

    nonisolated(unsafe) static let markdownHeading = #/^\h{0,3}#{1,6}\h+\S.*$/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let markdownFenceOpen = #/^\h*```[\w+-]*\h*$/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let markdownFenceClose = #/^\h*```\h*$/#
        .anchorsMatchLineEndings()

    /// A Ruby iterator block has a call before `do` and a block terminator on its own line.
    static func isRubyBlock(_ text: String) -> Bool {
        text.firstMatch(of: rubyBlockStart) != nil && text.firstMatch(of: rubyBlockEnd) != nil
    }

    nonisolated(unsafe) static let rubyBlockStart =
        #/^\h*(?:[\w.]+(?:\([^\n)]*\))?\h+do(?:\h+\|[^|\n]*\|)?|(?:def|class|module|if|unless|while|until|for|begin)\h+\S.*)$/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let rubyBlockEnd = #/^\h*end\h*$/#
        .anchorsMatchLineEndings()

    /// A sampled CSS id-selector rule with a declaration block and a terminated property.
    static func isCSSRule(in sample: String) -> Bool {
        let scalars = Array(sample.unicodeScalars)
        var index = 0
        skipHorizontalWhitespace(in: scalars, index: &index, before: scalars.count)
        guard consumeCSSSelectors(in: scalars, index: &index) else { return false }
        skipHorizontalWhitespace(in: scalars, index: &index, before: scalars.count)
        guard index < scalars.count, scalars[index] == "{" else { return false }
        index += 1
        let bodyStart = index
        while index < scalars.count, scalars[index] != "}" {
            guard scalars[index] != "{" else { return false }
            index += 1
        }
        guard index < scalars.count, hasTerminatedCSSProperty(in: scalars, from: bodyStart, to: index) else {
            return false
        }
        index += 1
        skipHorizontalWhitespace(in: scalars, index: &index, before: scalars.count)
        return index == scalars.count
    }

    /// Reads an id-selector list, stopping at its opening brace.
    private static func consumeCSSSelectors(in scalars: [Unicode.Scalar], index: inout Int) -> Bool {
        while true {
            guard index < scalars.count, scalars[index] == "#" else { return false }
            index += 1
            guard index < scalars.count, isCSSIdentifierStart(scalars[index]) else { return false }
            index += 1
            while index < scalars.count, isCSSIdentifierContinuation(scalars[index]) { index += 1 }
            skipHorizontalWhitespace(in: scalars, index: &index, before: scalars.count)
            guard index < scalars.count, scalars[index] == "," else { return true }
            index += 1
            skipHorizontalWhitespace(in: scalars, index: &index, before: scalars.count)
        }
    }

    /// Finds one property name, nonempty value and following semicolon in a single forward scan.
    private static func hasTerminatedCSSProperty(
        in scalars: [Unicode.Scalar], from start: Int, to end: Int
    ) -> Bool {
        var index = start
        var awaitingValue = false
        var hasValue = false
        while index < end {
            if scalars[index] == ";" {
                if hasValue { return true }
                awaitingValue = false
                hasValue = false
                index += 1
                continue
            }
            if awaitingValue, !CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
                hasValue = true
                awaitingValue = false
            }
            guard isCSSPropertyNameCharacter(scalars[index]) else {
                index += 1
                continue
            }
            let colon = endOfCSSPropertyName(in: scalars, from: index, to: end)
            if colon < end, scalars[colon] == ":" {
                awaitingValue = true
                index = colon + 1
            } else {
                index = max(index + 1, colon)
            }
        }
        return false
    }

    /// Returns the colon position after one maximal property name and its horizontal whitespace.
    private static func endOfCSSPropertyName(
        in scalars: [Unicode.Scalar], from start: Int, to end: Int
    ) -> Int {
        var index = start
        while index < end, isCSSPropertyNameCharacter(scalars[index]) { index += 1 }
        skipHorizontalWhitespace(in: scalars, index: &index, before: end)
        return index
    }

    /// Advances over horizontal whitespace without treating a line break as CSS spacing here.
    private static func skipHorizontalWhitespace(
        in scalars: [Unicode.Scalar], index: inout Int, before end: Int
    ) {
        while index < end, CharacterSet.whitespaces.contains(scalars[index]) { index += 1 }
    }

    private static func isCSSIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z") || scalar == "_"
    }

    private static func isCSSIdentifierContinuation(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "-" || isCSSWordScalar(scalar)
    }

    private static func isCSSWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber,
            .otherNumber, .connectorPunctuation:
            return true
        default:
            return false
        }
    }

    private static func isCSSPropertyNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z") || scalar == "-"
    }

    nonisolated(unsafe) static let goShortDeclaration = #/^\h*[A-Za-z_]\w*\h*:=\h*\S.*$/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let deferredCall = #/^\h*defer\h+[\w.$]+\([^\n)]*\)\h*$/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let javaGenericDeclaration =
        #/^\h*[A-Z][\w.]*<[^<>\n]+>\h+\w+\h*=\h*new\h+[A-Z][\w.]*<[^<>\n]*>\(\)\h*;\h*$/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let phpRequestAssignment =
        #/^\h*\$[A-Za-z_]\w*\h*=\h*\$_(?:GET|POST|REQUEST|SERVER|COOKIE|FILES)\s*\[/#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let moduleExportsAssignment =
        #/^\h*module\.exports(?:\.[\w$]+)?\h*=/#
        .anchorsMatchLineEndings()

    // MARK: - The signals

    /// Whether the text carries two independent hints of code, read cheapest first and stopping at the second.
    static func hasTwoSignals(in text: String) -> Bool {
        tally?.record(text.utf8.count)
        // A pattern runs only when the bytes hold a literal it cannot match without.
        func has(_ pattern: Regex<Substring>, needing literals: [StaticString]) -> Bool {
            ClipBytes.containsAny(text, literals) && text.firstMatch(of: pattern) != nil
        }
        // Both braces, read once so a closing brace cannot also score as a statement ending.
        let braces = text.contains("{") && text.contains("}")
        let signals: [() -> Bool] = [
            { braces },
            { hasStatementEnding(text, countingClosingBrace: !braces) },
            { isIndented(text) },
            { has(invocation, needing: ["("]) },
            { has(commentLine, needing: ["//", "/*", "*", "#", "--"]) },
            { text.firstMatch(of: query) != nil },
            { has(quotedMember, needing: ["\""]) },
            { has(shellFragment, needing: ["|", "&&", "$(", ">", "-"]) },
            {
                has(
                    controlFlow,
                    needing: ["(", "return", "throw", "break", "continue", "yield", "else", "elif", "endif"])
            },
            { has(codeOperator, needing: ["=>", "->", "::", "==", "&&", "||", "+=", "-=", "++", "!="]) },
            {
                has(
                    declaration,
                    needing: [
                        "func", "def", "fn", "sub", "class", "struct", "enum", "interface", "trait",
                        "protocol",
                        "actor", "let", "var", "const", "val", "public", "private", "internal", "static",
                        "async",
                        "await", "import", "from", "package", "using", "require", "#include",
                    ])
            },
        ]
        var found = 0
        for signal in signals where signal() {
            found += 1
            if found == 2 { return true }
        }
        return false
    }
}
