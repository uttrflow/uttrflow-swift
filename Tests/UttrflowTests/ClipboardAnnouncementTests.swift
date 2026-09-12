// Tests that every clipboard write is announced, by reading the source.

import Foundation
import Testing

@testable import Uttrflow

/// Every write Uttrflow makes to the clipboard is announced first; checked by reading the source.
@Suite("Uttrflow announces its own writes to the clipboard")
struct ClipboardAnnouncementTests {
    /// The package root, found from this file rather than from the working directory.
    private var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package
            .appending(path: "Sources/Uttrflow")
    }

    /// The source with its line comments taken out, so a sentence describing the rule cannot break it.
    private func code(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "//").first ?? "" }
            .joined(separator: "\n")
    }

    private func swiftFiles() throws -> [URL] {
        let walker = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)
        let files = walker?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        // A path that resolves to nothing looks exactly like a rule nobody is breaking.
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

    /// Every inserter the app builds must be given the announcing pasteboard.
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

    /// The announcement is not something a caller assembles for itself; one pasteboard exists.
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

    /// Reaching the platform clipboard at all is what let a write skip the announcement and the host-only clear.
    @Test("and it never reaches the platform clipboard itself")
    func theAppNamesNoPasteboard() throws {
        for file in try swiftFiles() {
            let source = try code(of: file)
            #expect(
                !source.contains("NSPasteboard"),
                """
                \(file.lastPathComponent) writes the clipboard itself, so it misses the \
                announcement and `.currentHostOnly` and sends the text to the user's other \
                devices. Go through `announcingPasteboard`. See `Scripts/pasteboard_audit.sh`.
                """)
        }
    }
}
