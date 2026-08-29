import Foundation
import Testing

@testable import Uttrflow

/// Every write Uttrflow makes to the clipboard is announced to the watcher first.
///
/// This is a seam, and it failed exactly the way seams fail here: the rule was obeyed at
/// one call site, written down in a doc comment on that call site, and quietly not obeyed
/// at the other. `SystemPasteboard`'s `willWrite` defaults to doing nothing — which is
/// right, since most callers never write — so the inserter the dictation pipeline was
/// built with compiled, ran, and recorded every pasted dictation a second time as a copy
/// from whichever application was in front. The store then merged the two by text and
/// took the arrival's provenance, so the word "Dictation" never once reached the disk.
///
/// Nothing about that is visible in a diff, in a type, or in the coverage report —
/// `AppDelegate` is excluded from it, because it assembles the real engines. So the guard
/// is a reading of the source, in the same spirit as `EvaluationSeparationTests`: it is
/// checking an assembly rule that has no other place to live.
@Suite("Uttrflow announces its own writes to the clipboard")
struct ClipboardAnnouncementTests {
    /// The package root, found from this file rather than from the working directory,
    /// which is wherever the test runner happened to be started.
    private var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package
            .appending(path: "Sources/Uttrflow")
    }

    /// The source with its line comments taken out.
    ///
    /// A rule about what the code does should not be broken by a sentence describing it —
    /// and the comment explaining this very rule names the trap it is about.
    private func code(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "//").first ?? "" }
            .joined(separator: "\n")
    }

    private func swiftFiles() throws -> [URL] {
        let walker = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)
        let files = walker?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        // A path that resolves to nothing looks exactly like a rule nobody is breaking,
        // which is how a check like this dies silently. See the account suite, which sat
        // skipped for days behind a stale path.
        #expect(files.count > 5, "no app sources found at \(appSources.path)")
        return files
    }

    /// The argument list of a call, from the opening bracket to its match.
    private func arguments(after call: String, in source: String) -> [String] {
        var found: [String] = []
        var search = source.startIndex..<source.endIndex
        while let start = source.range(of: call, range: search) {
            var depth = 0
            var index = source.index(before: start.upperBound)
            while index < source.endIndex {
                if source[index] == "(" { depth += 1 }
                if source[index] == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                index = source.index(after: index)
            }
            found.append(String(source[start.upperBound..<index]))
            search = index..<source.endIndex
        }
        return found
    }

    /// The bug this suite exists for: the dictation pipeline's inserter was built with
    /// the default pasteboard, and the panel's was not.
    @Test("every text inserter the app builds is given the announcing pasteboard")
    func everyInserterAnnounces() throws {
        for file in try swiftFiles() {
            let source = try code(of: file)
            for call in arguments(after: "TextInsertion.coordinator(", in: source) {
                #expect(
                    call.contains("pasteboard:"),
                    """
                    \(file.lastPathComponent) builds a text inserter without naming a \
                    pasteboard, so it gets SystemPasteboard() with an empty willWrite. \
                    Anything it pastes will be recorded a second time as a copy. Pass \
                    `pasteboard: announcingPasteboard`.
                    """)
            }
        }
    }

    /// And the announcement is not something a caller assembles for itself. One of these
    /// exists; the reason the two call sites could disagree is that there used to be two.
    @Test("and the app never builds a silent one")
    func noSilentPasteboards() throws {
        for file in try swiftFiles() {
            let source = try code(of: file)
            #expect(
                !source.contains("SystemPasteboard()"),
                """
                \(file.lastPathComponent) builds a pasteboard that tells the watcher \
                nothing. Use the app's one `announcingPasteboard`.
                """)
        }
    }

    /// The other half of the same rule, for the two places that reach `NSPasteboard`
    /// directly rather than through an inserter — pasting a picture, and putting a clip
    /// back when there is nowhere to insert it.
    @Test("and the writes it makes by hand announce themselves too")
    func directWritesAnnounce() throws {
        for file in try swiftFiles() {
            let source = try code(of: file)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() where line.contains("clearContents()") {
                // The announcement goes immediately *before* the write, which is what
                // makes it exact: a tick landing between the two still sees it. Ten lines
                // is room for the guard clauses that sit in between, and no more.
                let window = lines[max(0, number - 10)..<number].joined(separator: "\n")
                #expect(
                    window.contains("ignoreNextWrite()"),
                    """
                    \(file.lastPathComponent):\(number + 1) clears the clipboard without \
                    telling the watcher first, so the write will be read as a copy.
                    """)
            }
        }
    }
}
