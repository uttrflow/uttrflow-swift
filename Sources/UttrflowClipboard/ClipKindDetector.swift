// What a copied string is: link, colour, path, code or text.

import Foundation
public import UttrflowCore

/// Works out what a copied string is; secret is asked first because it is the only costly miss.
public enum ClipKindDetector {
    /// What this text is and, for code, which language, worked out on a utility-priority task off the caller's actor.
    public static func classify(_ text: String) async -> ClipClassification {
        await classify(text, using: classification(of:))
    }

    /// `classify(_:)` with the work supplied; a continuation, not `Task.value`, so awaiting it does not raise its priority.
    static func classify(
        _ text: String, using work: @escaping @Sendable (String) -> ClipClassification
    ) async -> ClipClassification {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) { continuation.resume(returning: work(text)) }
        }
    }

    /// What this text is and, for code, which language, worked out on the calling thread.
    public static func classification(of text: String) -> ClipClassification {
        let kind = kind(of: text)
        return ClipClassification(kind: kind, language: kind == .code ? CodeLanguage.detect(text) : nil)
    }

    /// What this text is, defaulting to `.text`, the answer that costs nothing when wrong. See `Docs/performance-idle.md`.
    public static func kind(of text: String) -> ClipKind {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        trimmed.makeContiguousUTF8()

        if SecretShapes.matches(trimmed) { return .secret }
        if ColourShape.matches(trimmed) { return .colour }
        if LinkShape.matches(trimmed) { return .link }
        // After link, because `file://` is an address; before code, because a path is punctuation.
        if PathShape.matches(trimmed) { return .filePath }
        if CodeShapes.matches(trimmed) { return .code }
        return .text
    }
}

/// A clip's kind and, when it is code, the language it is written in.
public struct ClipClassification: Sendable, Equatable {
    public let kind: ClipKind
    public let language: CodeLanguage?
}

/// A copied address or a clip made up of addresses, including common app-specific schemes.
enum LinkShape {
    /// Retained as the link-token oracle used by the classifier equivalence tests.
    nonisolated(unsafe) static let address = #/(?i)https?://[^\s/?#]\S*/#
    nonisolated(unsafe) private static let otherAddress =
        #/(?i)(?:ftp|file|mailto|tel|ssh|git|slack|obsidian|vscode|zoommtg|ws|wss|sftp|chrome):[^\s<>]+/#
    nonisolated(unsafe) private static let scpAddress = #/^[^\s@/:]+@[^\s/:]+:.+$/#
    nonisolated(unsafe) private static let markdownLink = #/^\[[^\]\n]+\]\(([^\s()]+)(?:\s+"[^"]*")?\)$/#
    nonisolated(unsafe) private static let listMarker = #/^(?:[-*+]\s+|\d+[.)]\s+)/#

    static func matches(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let nonblank = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = nonblank.first else { return false }

        // A list is a link only when every item resolves to an address.
        if nonblank.count > 1,
            nonblank.allSatisfy({ line in
                let item = line.replacing(listMarker, with: "")
                return isAddress(item)
            })
        {
            return true
        }

        // A copied page may place its title on a second line after the address.
        if nonblank.count == 2, isAddress(first), !isAddress(nonblank[1]) { return true }
        return isAddress(first)
    }

    private static func isAddress(_ source: String) -> Bool {
        let line = source.trimmingCharacters(in: .whitespaces)
        if let match = line.wholeMatch(of: markdownLink) {
            return isAddress(String(match.1))
        }

        var candidate = line
        // Unwrap conventional link punctuation without changing balanced parentheses in URLs.
        if candidate.count >= 2,
            let first = candidate.first, let last = candidate.last,
            (first == "<" && last == ">") || (first == "\"" && last == "\"")
                || (first == "'" && last == "'") || (first == "[" && last == "]")
                || (first == "(" && last == ")")
        {
            candidate.removeFirst()
            candidate.removeLast()
        }
        while let last = candidate.last, ".,;!?".contains(last) { candidate.removeLast() }
        while let last = candidate.last, ")]".contains(last) {
            let open = last == ")" ? "(" : "["
            if candidate.filter({ String($0) == open }).count
                >= candidate.filter({ String($0) == String(last) }).count
            {
                break
            }
            candidate.removeLast()
        }

        if candidate.wholeMatch(of: scpAddress) != nil { return true }
        guard candidate.wholeMatch(of: address) != nil || candidate.wholeMatch(of: otherAddress) != nil else {
            return false
        }
        guard let schemeEnd = candidate.firstIndex(of: ":") else { return false }
        let scheme = candidate[..<schemeEnd].lowercased()
        guard let components = URLComponents(string: candidate), components.scheme != nil else {
            return false
        }
        if scheme == "http" || scheme == "https" || scheme == "ftp" || scheme == "ssh" || scheme == "ws"
            || scheme == "wss" || scheme == "sftp"
        {
            return components.host?.isEmpty == false
        }
        if scheme == "file" { return components.host?.isEmpty == false || !components.path.isEmpty }
        if scheme == "mailto" || scheme == "tel" { return !components.path.isEmpty }
        return true
    }
}

/// A colour in the notations a designer copies; which colour it is lives in `ColourValue`.
enum ColourShape {
    /// Three, four, six or eight hex digits behind a compulsory `#`, which keeps `dad` and `facade` off.
    nonisolated(unsafe) private static let hex =
        #/#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})/#

    /// The functional notations with no nesting inside the brackets, so a function call is not a colour.
    nonisolated(unsafe) static let functional =
        #/(?i)(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\([^()]+\)/#

    static func matches(_ text: String) -> Bool {
        text.wholeMatch(of: hex) != nil || text.wholeMatch(of: functional) != nil
    }
}

/// Whether a copy is worth recording at all, shared by the watcher and the store.
enum ClipContent {
    /// Whitespace and nothing else is not a clip; applications write stray newlines constantly.
    static func isWorthKeeping(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A path to a file or folder on this Mac, and only when the whole clip is the path.
enum PathShape {
    /// The prefixes that make a path a path; bare `Users/x` is how people write most things with slashes.
    static let starts = ["/", "~/", "./", "../"]

    static func matches(_ text: String) -> Bool {
        // One line: a path with a newline in it is a list or a paragraph.
        guard !text.contains(where: \.isNewline) else { return false }
        guard text.count <= 4096 else { return false }
        guard starts.contains(where: text.hasPrefix) else { return false }
        // `~` alone, or `/` alone, is a shell shorthand rather than a clip worth filing.
        guard text.count > 2 else { return false }

        // A flag in any component makes this look like a command, not a copied path.
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.hasPrefix("-") }) else { return false }
        guard (text.hasPrefix("/") || text.hasPrefix("~/")), text.dropFirst().contains("/") else {
            return false
        }

        // Characters no filesystem path carries, which code and prose use constantly.
        let forbidden: Set<Character> = ["|", "*", "<", ">", "\"", "\n", "\t"]
        return !text.contains(where: forbidden.contains)
    }
}
