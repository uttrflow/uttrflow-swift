import Foundation

extension CaretStructure {
    /// What kind of text the caret stands in, read from the document's language. See `Docs/cleanup-design.md`.
    public enum Region: Sendable, Equatable {
        /// Executable source of a recognised language.
        case code
        /// An unclosed string literal in executable source.
        case string
        /// A line comment, block comment or docstring.
        case comment
        /// Body prose of a Markdown or plain-text document: any line but a `#` heading.
        case prose
        /// An unrecognised or untitled document, or a Markdown heading.
        case unrecognised

        /// Whether the caret sits in executable source, inside a string literal or not.
        public var isCode: Bool { self == .code || self == .string }
    }

    /// Classifies the caret by scanning the text before it in the document's language.
    public static func region(precedingText: String?, documentName: String?) -> Region {
        guard let ext = fileExtension(from: documentName) else { return .unrecognised }
        if proseExtensions.contains(ext) {
            return caretLine(of: precedingText ?? "").drop(while: { $0 == " " }).hasPrefix("#")
                ? .unrecognised : .prose
        }
        guard let markers = markers(forExtension: ext) else { return .unrecognised }
        return precedingText.map { scan($0, markers: markers) } ?? .code
    }

    /// Whether the caret stands where a comment's first word goes: in a comment, with no word after its opener on the caret's line.
    package static func opensComment(precedingText: String?, documentName: String?) -> Bool {
        guard region(precedingText: precedingText, documentName: documentName) == .comment,
            let markers = fileExtension(from: documentName).flatMap(markers(forExtension:))
        else { return false }
        let line = caretLine(of: precedingText ?? "")
        let afterLastWord = line.reversed().prefix { !$0.isLetter && !$0.isNumber }
        guard afterLastWord.count < line.count else { return true }
        let openers = markers.line + (markers.block.map { [$0.open] } ?? []) + markers.docstrings.map(\.open)
        return openers.contains { String(afterLastWord.reversed()).contains($0) }
    }

    private static let proseExtensions: Set<String> = ["md", "markdown", "txt"]
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// Whether the document is a Markdown file, which is where raw Markdown marks render rather than show.
    public static func isMarkdown(documentName: String?) -> Bool {
        fileExtension(from: documentName).map(markdownExtensions.contains) ?? false
    }

    private struct Markers {
        let line: [String]
        let block: (open: String, close: String)?
        var docstrings: [QuoteStyle] = []
    }

    /// Python string delimiters that, left open, hold a docstring rather than a value.
    private static let pythonDocstrings: [QuoteStyle] = ["\"\"\"", "'''"].map {
        QuoteStyle(open: $0, close: $0, literal: .backslash, escapes: [:])
    }

    /// Comment markers count only in code, outside strings, so a marker after code on the caret's line opens a comment.
    private static func scan(_ text: String, markers: Markers) -> Region {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            if depth > 0, let block = markers.block {
                if text[index...].hasPrefix(block.close) {
                    depth -= 1
                    index = text.index(index, offsetBy: block.close.count)
                } else if text[index...].hasPrefix(block.open) {
                    depth += 1
                    index = text.index(index, offsetBy: block.open.count)
                } else {
                    index = text.index(after: index)
                }
                continue
            }
            if markers.line.contains(where: { text[index...].hasPrefix($0) }) {
                guard let newline = text[index...].firstIndex(where: \.isNewline) else { return .comment }
                index = text.index(after: newline)
                continue
            }
            switch Quoting.opening(in: text, at: index, styles: markers.docstrings) {
            case .closed(let end):
                index = end
                continue
            case .unclosed:
                return .comment
            case .none:
                break
            }
            switch Quoting.opening(in: text, at: index, styles: QuoteStyle.sourceStrings) {
            case .closed(let end):
                index = end
                continue
            case .unclosed:
                return .string
            case .none:
                break
            }
            if let block = markers.block, text[index...].hasPrefix(block.open) {
                depth += 1
                index = text.index(index, offsetBy: block.open.count)
            } else {
                index = text.index(after: index)
            }
        }
        return depth > 0 ? .comment : .code
    }

    /// The comment markers for a file extension's language, or `nil` for an unrecognised one.
    private static func markers(forExtension ext: String) -> Markers? {
        switch ext {
        case "swift", "js", "jsx", "mjs", "cjs", "ts", "tsx", "java", "kt", "kts",
            "c", "h", "cc", "cpp", "cxx", "hpp", "m", "mm", "go", "rs", "cs", "php", "scala", "dart":
            return Markers(line: ["//"], block: ("/*", "*/"))
        case "py":
            return Markers(line: ["#"], block: nil, docstrings: pythonDocstrings)
        case "rb", "sh", "bash", "zsh", "fish", "yaml", "yml", "pl", "r":
            return Markers(line: ["#"], block: nil)
        case "sql":
            return Markers(line: ["--"], block: ("/*", "*/"))
        case "lua":
            return Markers(line: ["--"], block: ("--[[", "]]"))
        case "html", "htm", "xml":
            return Markers(line: [], block: ("<!--", "-->"))
        case "css", "scss", "less":
            return Markers(line: [], block: ("/*", "*/"))
        default:
            return nil
        }
    }

    /// The extension of the first filename-shaped token in a document name, which may carry a window title after it.
    private static func fileExtension(from documentName: String?) -> String? {
        guard let documentName else { return nil }
        for token in documentName.split(separator: " ") where token.contains(".") {
            guard let ext = token.split(separator: ".").last, !ext.isEmpty else { continue }
            return String(ext).lowercased()
        }
        return nil
    }
}
