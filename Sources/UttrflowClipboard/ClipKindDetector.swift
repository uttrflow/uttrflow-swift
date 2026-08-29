import Foundation

/// Works out what a copied string is, so the list can be scanned rather than read.
///
/// Pure, synchronous and dependency-free on purpose. It runs on the copy path, dozens
/// of times an hour, before anything is written to disk — anything it had to wait for
/// would be a wait imposed on ⌘C itself. Being pure also means a wrong answer is a
/// failing test rather than a bug report, which matters most for ``ClipKind/secret``.
///
/// The order below is the whole design. ``ClipKind/secret`` is asked first because it
/// is the only answer with a cost attached: a connection string that is also a URL is
/// a credential first and a link second, and masking it wrongly loses nothing but a
/// preview, while missing it puts a production password on a shared screen. Colour
/// comes before link and code because `rgb(0, 0, 0)` is parenthesised and `#fff` is
/// short, and both would otherwise be read as something they are not.
public enum ClipKindDetector {
    /// What this text is.
    ///
    /// - Parameter text: Exactly what was copied, untrimmed.
    /// - Returns: The kind, defaulting to ``ClipKind/text`` — which most things are, and
    ///   which is the answer that costs the user nothing when it is wrong.
    public static func kind(of text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        if SecretShapes.matches(trimmed) { return .secret }
        if ColourShape.matches(trimmed) { return .colour }
        if LinkShape.matches(trimmed) { return .link }
        // Before code, because a path is one line of punctuation and slashes that several
        // of code's signals also match; after link, because `file://…` is an address and
        // reads as one.
        if PathShape.matches(trimmed) { return .filePath }
        if CodeShapes.matches(trimmed) { return .code }
        return .text
    }
}

/// A web address, and nothing that merely resembles one.
enum LinkShape {
    /// A scheme is compulsory, which is what keeps the near-misses out: a bare
    /// `example.com` could as easily be a sentence fragment, and `someone@example.com` is
    /// an address you write to rather than one you visit. Both are ``ClipKind/text``, and
    /// a user who wants them pasted gets them pasted.
    ///
    /// `/usr/local/bin` used to be listed here as a third near-miss. It is now
    /// ``ClipKind/filePath``, which is where it belonged.
    ///
    /// `file://` is deliberately still not a link, and is not a path either: what such a
    /// clip *holds* is the URL, so labelling it a path would put a folder icon on a string
    /// that no terminal will accept. It stays text until there is a reason to do better.
    ///
    /// The tail is deliberately permissive — query strings and fragments carry `?`, `#`,
    /// `=` and `&` — and bounded only by whitespace, because a link with a space in it
    /// is two things, not one.
    nonisolated(unsafe) private static let address = #/(?i)https?://[^\s/?#]+\S*/#

    static func matches(_ text: String) -> Bool { text.wholeMatch(of: address) != nil }
}

/// A colour, in the notations a designer actually copies out of a tool.
///
/// Only whether the text *is* one. Which colour it is lives in ``ColourValue``, is a
/// harder question, and has no answer for some of what is matched here.
enum ColourShape {
    /// Three, four, six or eight hex digits: `#f0a`, `#f0ac`, `#ff00aa`, `#ff00aacc`.
    /// Five and seven are not colours in any notation, so they are not accepted as one.
    ///
    /// The `#` is compulsory, which is the one judgement call in this file. Bare `fff`
    /// is a colour a designer might paste, but `dad`, `bed`, `fee`, `ace`, `decade`,
    /// `facade` and `deeded` are hex digits too, and they are ordinary words of exactly
    /// the length someone copies on its own. Requiring the hash costs the designer
    /// nothing — every tool that emits hex emits the hash with it — and it is the only
    /// way to keep a swatch off a three-letter word.
    nonisolated(unsafe) private static let hex =
        #/#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})/#

    /// The functional notations, including the newer perceptual ones that design tools
    /// now emit. No nesting is allowed inside the brackets, which is what stops an
    /// ordinary function call being read as a colour.
    nonisolated(unsafe) private static let functional =
        #/(?i)(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(\s*[^()]+\)/#

    static func matches(_ text: String) -> Bool {
        text.wholeMatch(of: hex) != nil || text.wholeMatch(of: functional) != nil
    }
}

/// Whether a copy is worth recording at all.
///
/// Shared by the watcher and the store rather than written twice. The watcher uses it
/// to avoid waking the disk for nothing; the store uses it because "refuse an empty
/// copy" is a promise about what is stored, and a promise only the caller keeps is not
/// one.
enum ClipContent {
    /// Whitespace and nothing else is not a clip.
    ///
    /// Applications write a stray newline to the clipboard more often than anyone would
    /// guess — a triple-click that caught only a line ending, a table cell that was
    /// empty. A row for it is a row the user has to arrow past, and pasting it does
    /// nothing visible, so it is never worth one.
    static func isWorthKeeping(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// K5 — a path to a file or folder on this Mac.
///
/// Deliberately narrow. A path is a shape almost anything can wear — a date reads as
/// `2026/08/24`, a fraction as `1/2`, a regular expression as `/^a.*b$/` — so this asks
/// for evidence that somebody's filesystem is involved rather than merely that a slash is.
///
/// The whole clip must be the path. A sentence mentioning one is a sentence, and a command
/// line containing one is code; both are clips people keep, and relabelling them would put
/// a folder icon on the wrong thing.
enum PathShape {
    /// The prefixes that make a path a path.
    ///
    /// A leading `~` or `/` is somebody's home or root. A relative `./` or `../` says the
    /// author meant a path rather than happened to type a slash. Bare `Users/naveen/x` is
    /// deliberately excluded: it is also how people write most things with slashes in.
    static let starts = ["/", "~/", "./", "../"]

    static func matches(_ text: String) -> Bool {
        // One line. A path with a newline in it is a list of paths or a paragraph, and
        // either way it is not one file.
        guard !text.contains(where: \.isNewline) else { return false }
        guard text.count <= 4096 else { return false }
        guard starts.contains(where: text.hasPrefix) else { return false }
        // `~` alone, or `/` alone, is a shell shorthand rather than a clip worth filing.
        guard text.count > 2 else { return false }

        // Spaces are where paths and shell commands become the same shape, and banning
        // them outright costs too much: `~/Library/Application Support/…` is one of the
        // commonest paths on the platform, and this app's own storage lives there.
        //
        // So: at most one space, and no argument. A folder name with a space in it is
        // ordinary — "Application Support", "My Notes.txt" — while a command is a verb
        // followed by *several* things, and usually by a flag. `./deploy.sh --force` is
        // rejected for the flag, `/usr/bin/env ruby x.rb` for the second space.
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        guard !parts.contains(where: { $0.hasPrefix("-") }) else { return false }
        guard text.dropFirst().contains("/") || text.hasPrefix("~/") || text.hasPrefix("./")
        else { return false }

        // Characters no filesystem path carries, and which appear constantly in the code
        // and prose this must not steal from.
        let forbidden: Set<Character> = ["|", "*", "<", ">", "\"", "\n", "\t"]
        return !text.contains(where: forbidden.contains)
    }
}
