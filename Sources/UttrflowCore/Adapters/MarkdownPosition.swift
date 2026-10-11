/// Where the caret stands in a Markdown document, read from the text before it: the list, heading and fence already written.
package struct MarkdownPosition: Sendable, Equatable {
    /// The kind of list item the caret's line is.
    package enum ListKind: Sendable, Equatable {
        case bullet(marker: Character)
        case numbered(number: Int, delimiter: Character)
        case task(marker: Character)
    }

    /// The list item the caret's line opens with, or `nil` where the line is no item.
    package let list: ListKind?
    /// Whether the caret's item has no words after its mark yet.
    package let itemIsEmpty: Bool
    /// The blockquote marks and indent the caret's line opens with, repeated on a continuation.
    package let linePrefix: String
    /// How many blockquote marks the caret's line opens with.
    package let quoteDepth: Int
    /// The level of the last heading above the caret, outside any fence.
    package let lastHeadingLevel: Int?
    /// The language of the fence still open at the caret, empty for a fence without one, or `nil` outside a fence.
    package let fenceLanguage: String?
    /// Whether the caret's line holds nothing but whitespace, or the text is empty.
    package let isOnBlankLine: Bool
    /// The window began mid-document, so a heading or fence above may be unseen.
    package let isCut: Bool

    /// Whether the caret stands inside a fenced block.
    package var isInFence: Bool { fenceLanguage != nil }

    /// Nothing known: the answer for a field that will not say.
    package static let unknown = MarkdownPosition(
        list: nil, itemIsEmpty: false, linePrefix: "", quoteDepth: 0, lastHeadingLevel: nil,
        fenceLanguage: nil, isOnBlankLine: false, isCut: true)

    /// The mark of the item that follows the caret's, `skipping` items already written after it, or `nil` outside a list, in a fence or on an empty item.
    package func continuation(skipping count: Int = 0) -> String? {
        guard let list, !isInFence, !itemIsEmpty else { return nil }
        switch list {
        case .bullet(let marker): return linePrefix + "\(marker) "
        case .task(let marker): return linePrefix + "\(marker) [ ] "
        case .numbered(let number, let delimiter):
            return linePrefix + "\(number + 1 + count)\(delimiter) "
        }
    }

    /// The mark of a heading one level below the last, or `nil` in a fence or where no heading is seen and the window is cut.
    package var nextHeading: String? {
        guard !isInFence, lastHeadingLevel != nil || !isCut else { return nil }
        return String(repeating: "#", count: min((lastHeadingLevel ?? 0) + 1, 6))
    }

    /// Reads the position at the end of `precedingText`; `nil` text, as a field that will not say, is `unknown`.
    package static func at(_ precedingText: String?) -> MarkdownPosition {
        guard let precedingText else { return .unknown }
        let text = InsertionPoint.visibleText(precedingText)
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let caretLine = lines.last ?? ""
        var fence: Fence?
        var heading: Int?
        for line in lines.dropLast() {
            if let open = fence {
                if open.isClosed(by: line) { fence = nil }
            } else if let opened = Fence(opening: line) {
                fence = opened
            } else if let level = headingLevel(of: line) {
                heading = level
            }
        }
        let opensFence = fence == nil && Fence(opening: caretLine) != nil
        if fence == nil, !opensFence, let level = headingLevel(of: caretLine) { heading = level }
        let item = fence == nil && !opensFence ? ListItem(line: caretLine) : nil
        return MarkdownPosition(
            list: item?.kind, itemIsEmpty: item?.isEmpty ?? false, linePrefix: item?.prefix ?? "",
            quoteDepth: item?.quoteDepth ?? 0, lastHeadingLevel: heading,
            fenceLanguage: fence?.language,
            isOnBlankLine: caretLine.allSatisfy(\.isWhitespace),
            isCut: text.utf16.count >= InsertionPoint.precedingLimit)
    }

    // MARK: Reading

    /// An open fenced block: the mark it opened with and the language after it.
    private struct Fence {
        let mark: Character
        let length: Int
        let language: String

        init?(opening line: Substring) {
            let body = line.drop(while: { $0 == " " || $0 == "\t" })
            guard let mark = body.first, mark == "`" || mark == "~" else { return nil }
            let run = body.prefix { $0 == mark }
            guard run.count >= 3 else { return nil }
            let info = body.dropFirst(run.count).drop(while: \.isWhitespace)
            // A backtick fence's info string holds no backtick, or the line is inline code.
            guard mark == "~" || !info.contains("`") else { return nil }
            self.mark = mark
            length = run.count
            language = info.prefix { !$0.isWhitespace && $0 != "{" }.lowercased()
        }

        func isClosed(by line: Substring) -> Bool {
            let body = line.drop(while: { $0 == " " || $0 == "\t" })
            let run = body.prefix { $0 == mark }
            return run.count >= length && body.dropFirst(run.count).allSatisfy(\.isWhitespace)
        }
    }

    /// The caret's line read as a list item inside any blockquote marks.
    private struct ListItem {
        let kind: ListKind
        let isEmpty: Bool
        let prefix: String
        let quoteDepth: Int

        init?(line: Substring) {
            var rest = line
            var depth = 0
            var quotes = ""
            while true {
                let trimmed = rest.drop(while: { $0 == " " })
                guard trimmed.first == ">" else { break }
                depth += 1
                quotes += "> "
                rest = trimmed.dropFirst()
                if rest.first == " " { rest = rest.dropFirst() }
            }
            let indent = String(rest.prefix { $0 == " " || $0 == "\t" })
            let body = rest.dropFirst(indent.count)
            guard let (kind, remainder) = Self.mark(of: body) else { return nil }
            self.kind = kind
            isEmpty = remainder.allSatisfy(\.isWhitespace)
            prefix = quotes + indent
            quoteDepth = depth
        }

        private static func mark(of body: Substring) -> (ListKind, Substring)? {
            if let marker = body.first, "-*+\u{2022}".contains(marker), body.dropFirst().first == " " {
                let remainder = body.dropFirst(2)
                for box in ["[ ]", "[x]", "[X]"] where remainder.hasPrefix(box) {
                    let after = remainder.dropFirst(box.count)
                    if after.isEmpty || after.first == " " { return (.task(marker: marker), after) }
                }
                return (.bullet(marker: marker), remainder)
            }
            let digits = body.prefix { $0.isASCII && $0.isNumber }
            let tail = body.dropFirst(digits.count)
            guard (1...9).contains(digits.count), let delimiter = tail.first, ".)".contains(delimiter),
                tail.dropFirst().first == " ", let number = Int(digits)
            else { return nil }
            return (.numbered(number: number, delimiter: delimiter), tail.dropFirst(2))
        }
    }

    /// The level of an ATX heading line: one to six marks and a space, up to three spaces in.
    private static func headingLevel(of line: Substring) -> Int? {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3 else { return nil }
        let marks = line.dropFirst(indent.count).prefix { $0 == "#" }
        let after = line.dropFirst(indent.count + marks.count)
        guard (1...6).contains(marks.count), after.isEmpty || after.first == " " else { return nil }
        return marks.count
    }

    private init(
        list: ListKind?, itemIsEmpty: Bool, linePrefix: String, quoteDepth: Int, lastHeadingLevel: Int?,
        fenceLanguage: String?, isOnBlankLine: Bool, isCut: Bool
    ) {
        self.list = list
        self.itemIsEmpty = itemIsEmpty
        self.linePrefix = linePrefix
        self.quoteDepth = quoteDepth
        self.lastHeadingLevel = lastHeadingLevel
        self.fenceLanguage = fenceLanguage
        self.isOnBlankLine = isOnBlankLine
        self.isCut = isCut
    }
}
