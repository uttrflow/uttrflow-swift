// A local "Report this dictation" bundle: masked by default, shared as exactly the lines the preview shows.
import UttrflowCore
package import struct Foundation.Data
import RegexBuilder

/// A text report of one dictation that a person reads, edits and copies or saves; nothing here sends it.
package struct DictationReport: Sendable, Equatable {
    /// The lines the preview shows, in order; the shared bytes are built from these and nothing else.
    package private(set) var lines: [String]

    /// Builds the report for `record`, masking secrets, email addresses, long digit runs and `names`.
    package init(record: DictationRecord, names: [String] = []) {
        let masker = ReportMasker(names: names)
        var lines = [
            "Uttrflow dictation report",
            "Audio: never included",
            "Cleaned by: \(record.cleanedBy?.rawValue ?? "unrecorded")",
            "Application: \(record.applicationIdentifier ?? "unrecorded")",
            "Error class: \(record.flagReason?.rawValue ?? "unlabelled")",
        ]
        for correction in record.changes?.corrections ?? [] where !correction.isUndone {
            lines.append(
                "Changed: \(masker.masked(correction.heard)) -> \(masker.masked(correction.wrote))")
        }
        lines.append("Text: \(masker.masked(record.text))")
        self.lines = lines
    }

    /// The report as shared: every line followed by a line break.
    package var text: String { lines.map { $0 + "\n" }.joined() }

    /// The bytes a copy or a saved file holds; always the UTF-8 of ``text``.
    package var bytes: Data { Data(text.utf8) }

    /// Takes the line at `index` out of the report; an index past the end changes nothing.
    package mutating func removeLine(at index: Int) {
        guard lines.indices.contains(index) else { return }
        lines.remove(at: index)
    }

    /// Replaces the line at `index` with the person's edit; a line break in it starts new lines.
    package mutating func replaceLine(at index: Int, with edited: String) {
        guard lines.indices.contains(index) else { return }
        lines.replaceSubrange(
            index...index,
            with: edited.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
    }
}

/// Replaces personal and secret-shaped spans with a bracketed class name before any line is shown.
struct ReportMasker {
    /// The fewest digits in a run of digits and separators that is masked as a number.
    static let longDigitRun = 6

    private let names: [String]

    init(names: [String]) {
        self.names = names.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    func masked(_ text: String) -> String {
        var text = text.replacing(Self.email, with: "[email]")
        text = text.replacing(Self.digitRun) { match in
            match.output.filter(\.isNumber).count >= Self.longDigitRun ? "[number]" : match.output
        }
        text = maskingSecretWords(text)
        for name in names {
            let whole = Regex {
                Anchor.wordBoundary
                name
                Anchor.wordBoundary
            }
            text = text.replacing(whole.ignoresCase(), with: "[name]")
        }
        return text
    }

    /// Each whitespace-separated word that reads as a credential, as the clipboard judges one.
    private func maskingSecretWords(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { SecretShapes.matches(String($0)) ? "[secret]" : String($0) }
            .joined(separator: " ")
    }

    private static var email: Regex<Substring> {
        /[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+/
    }
    private static var digitRun: Regex<Substring> { /[0-9](?:[ \-.]?[0-9])*/ }
}
