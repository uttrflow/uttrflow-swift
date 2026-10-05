// Tests that every bundle identifier written in the package resolves to a destination table row.

import Foundation
import Testing
import UttrflowCore

/// A mistyped identifier classifies as plain text and its case still passes, so every literal is checked here.
@Suite("Bundle identifier literals")
struct BundleIdentifierLiteralTests {
    /// Apps and system identifiers that are deliberately not destination rows, and the reserved example space.
    static let allowedPrefixes = [
        "com.example", "com.uttrflow.", "co.uttrflow.", "org.nspasteboard.", "com.apple.keylayout.",
    ]

    /// Real identifiers the package names on purpose without giving them a row.
    static let allowedExactly: Set<String> = [
        "com.apple.safari", "org.mozilla.firefox", "com.apple.finder", "com.anthropic.claudefordesktop",
        "com.jetbrains.toolbox", "com.linear.app", "com.apple.hitoolbox", "com.apple.screenislocked",
        "com.apple.universalaccess", "com.apple.keyboard-settings.extension",
        "com.apple.siri-settings.extension", "com.tinyspeck", "com.uttrflower.notes",
    ]

    /// Every prefix the table matches, compared the way the classifier compares.
    static let tablePrefixes: [String] =
        DestinationRules.standard.flatMap(\.bundlePrefixes).map { $0.lowercased() }
        + DestinationRules.chromiumBrowsers.map { $0.lowercased() }

    /// Whether an identifier reaches a table row or is one the package names on purpose.
    static func resolves(_ identifier: String) -> Bool {
        let key = identifier.lowercased()
        return tablePrefixes.contains { key.hasPrefix($0) }
            || allowedPrefixes.contains { key.hasPrefix($0) }
            || allowedExactly.contains(key)
    }

    @Test("every bundle-identifier literal in Sources and Tests resolves to a row or an allowed app")
    func everyLiteralResolves() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let labels = "com|org|net|dev|io|md|notion|at|ru|desktop|co|company"
        let pattern = try Regex(#""((?:"# + labels + #")\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)""#)
        let ownName = URL(fileURLWithPath: #filePath).lastPathComponent
        var unresolved: [String] = []
        for folder in ["Sources", "Tests"] {
            let files = FileManager.default.enumerator(
                at: root.appending(path: folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift", url.lastPathComponent != ownName,
                    let text = try? String(contentsOf: url, encoding: .utf8)
                else { continue }
                for match in text.matches(of: pattern) {
                    guard let literal = match.output[1].substring.map(String.init) else { continue }
                    if !Self.resolves(literal) { unresolved.append("\(url.lastPathComponent): \(literal)") }
                }
            }
        }
        #expect(unresolved.isEmpty, "identifiers with no row: \(unresolved)")
    }

    @Test("a mistyped identifier does not resolve, and the named entries do")
    func mistypedIdentifierFails() {
        #expect(!Self.resolves("com.tinyspek.slackmacgap"))
        #expect(!Self.resolves("com.apple.dt.Xcod"))
        let named = [
            DestinationRules.slack, DestinationRules.xcode, DestinationRules.cursor, DestinationRules.vsCode,
        ]
        for identifier in named {
            #expect(Self.resolves(identifier))
        }
    }
}
