// Proves every app the shipped source names is one the destination table already knows.
import Foundation
import Testing
import UttrflowCore

/// Issue #203: a second list of apps beside `DestinationRules.standard` drifts from it in silence.
@Suite("One app table")
struct OneAppTableTests {
    /// The package root, found from this file rather than from wherever the test runner started.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package
    }

    /// The one table, which is the only file allowed to name an app no row covers yet.
    static let theTable = "Sources/UttrflowCore/Models/DestinationRules.swift"

    /// Reverse-DNS roots an app identifier starts with, which is what separates one from `doc.on.doc`.
    static let roots: Set<String> = [
        "at", "cc", "co", "com", "de", "desktop", "dev", "io", "md", "me", "net", "org", "ru", "uk",
    ]

    /// Identifiers the source names that the table does not cover; an entry may leave this list, none may join.
    static let owed: Set<String> = [
        // Every one is `UttrflowPredict`'s own editor or terminal list, which that module cannot yet share.
        "co.zeit.hyper",
        "com.github.wez.wezterm",
        "com.jetbrains",  // the family prefix, which the table spells `com.jetbrains.` to sort DataGrip first
        "com.visualstudio.code",
        "io.alacritty",  // Alacritty ships as `org.alacritty`, so this row reaches nothing
        "org.tabby",
        "org.vim.macvim",
    ]

    /// Where each identifier named outside the table is named, lower-cased as the classifier reads it.
    private func namedIdentifiers() throws -> [String: [String]] {
        let sources = packageRoot.appending(path: "Sources")
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        else { return [:] }
        var found: [String: [String]] = [:]
        for file in walker.compactMap({ $0 as? URL }) where file.pathExtension == "swift" {
            let path = file.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
            guard path != Self.theTable else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() {
                for identifier in Self.identifiers(in: String(line)) {
                    found[identifier, default: []].append("\(path):\(number + 1)")
                }
            }
        }
        return found
    }

    /// The app identifiers one line quotes, which is every reverse-DNS literal that is not ours or a fixture.
    static func identifiers(in line: String) -> [String] {
        let quoted = line.split(separator: "\"", omittingEmptySubsequences: false)
            .enumerated().filter { $0.offset.isMultiple(of: 2) == false }.map { String($0.element) }
        return quoted.map { $0.lowercased() }.filter(isAppIdentifier)
    }

    /// Whether a literal is shaped like an app identifier: reverse-DNS, rooted, and neither ours nor a fixture.
    static func isAppIdentifier(_ literal: String) -> Bool {
        let parts = literal.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1, let root = parts.first, roots.contains(String(root)) else { return false }
        guard !["uttrflow", "example"].contains(String(parts[1])) else { return false }
        return parts.allSatisfy { part in
            part.first?.isLetter == true && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    /// Whether the one table has an answer for this identifier on the identifier alone.
    private func isKnown(_ identifier: String) -> Bool {
        DestinationClassifier.classify(AppContext(bundleIdentifier: identifier)) != .plain
    }

    /// An audit that scans nothing reports success, so the scan proves it found the source first.
    @Test("the scan reads the shipped source")
    func theScanReadsSomething() throws {
        #expect(try namedIdentifiers().count > 20)
    }

    /// A new app named anywhere but the one table is the divergence issue #203 was: two lists, one silent.
    @Test("every app the source names is one the table knows")
    func everyNamedAppIsClassified() throws {
        let unknown = try namedIdentifiers()
            .filter { !Self.owed.contains($0.key) && !isKnown($0.key) }
            .map { "\($0.key) (\($0.value[0]))" }
            .sorted()
        #expect(
            unknown.isEmpty,
            """
            \(unknown.joined(separator: ", ")) is named outside \(Self.theTable) and reaches no row in \
            it, so the words go to plain text. Add the app to DestinationRules.standard.
            """)
    }

    /// The list only shrinks: an identifier the table has since learned must leave it.
    @Test("nothing on the owed list is one the table now knows")
    func theOwedListOnlyShrinks() {
        let learned = Self.owed.filter { isKnown($0) }.sorted()
        let names = learned.joined(separator: ", ")
        #expect(names.isEmpty, "\(names) is covered by the table now — delete it from `owed`")
    }

    /// An entry for an identifier nothing says any more hides the next one behind it.
    @Test("the owed list names nothing the source has stopped saying")
    func theOwedListIsNotStale() throws {
        let named = try namedIdentifiers()
        let stale = Self.owed.filter { named[$0] == nil }.sorted()
        let names = stale.joined(separator: ", ")
        #expect(stale.isEmpty, "\(names) is named nowhere now — delete it from `owed`")
    }
}
