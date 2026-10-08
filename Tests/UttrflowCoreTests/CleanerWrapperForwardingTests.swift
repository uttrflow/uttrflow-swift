// Tests that a cleaner wrapping another cleaner passes on every requirement of the protocol.

import Foundation
import Testing

/// Reads the package's sources, since a requirement a wrapper leaves out still compiles against its default.
@Suite("Cleaner wrappers")
struct CleanerWrapperForwardingTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // UttrflowCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // package root
        .appending(path: "Sources")

    @Test("a cleaner that wraps another declares every requirement of TranscriptCleaning")
    func wrappersForwardEveryRequirement() throws {
        let protocolFile = Self.sources.appending(path: "UttrflowCore/Protocols/TranscriptCleaning.swift")
        let protocolText = try String(contentsOf: protocolFile, encoding: .utf8)
        let requirementBody = try #require(
            Self.body(after: "public protocol TranscriptCleaning", in: protocolText))
        let requirements = Self.declaredNames(in: requirementBody)
        #expect(requirements.count >= 5, "the requirement scan found only \(requirements)")

        var wrappers = 0
        let files = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for body in Self.conformingBodies(in: text) where body.contains("inner.") {
                wrappers += 1
                let declared = Self.declaredNames(in: body)
                for requirement in requirements {
                    #expect(
                        declared.contains(requirement),
                        "\(url.lastPathComponent) wraps a cleaner but leaves \(requirement) to the protocol default"
                    )
                }
            }
        }
        #expect(wrappers > 0, "no wrapping cleaner found, so this test checks nothing")
    }

    /// The names a body declares with `func` or `var`, at any depth.
    private static func declaredNames(in body: Substring) -> Set<String> {
        let pattern = /(?m)^\s*(?:public\s+)?(?:func|var)\s+(\w+)/
        return Set(body.matches(of: pattern).map { String($0.output.1) })
    }

    /// The bodies of every type in `text` declared as conforming to `TranscriptCleaning`.
    private static func conformingBodies(in text: String) -> [Substring] {
        let pattern =
            /(?:struct|final class|class|actor)\s+\w+(?:<[^>]*>)?\s*:[^{]*\bTranscriptCleaning\b[^{]*/
        return text.matches(of: pattern).compactMap { match in body(from: match.range.upperBound, in: text) }
    }

    /// The braced body that follows the first `marker` in `text`.
    private static func body(after marker: String, in text: String) -> Substring? {
        guard let found = text.range(of: marker) else { return nil }
        return body(from: found.upperBound, in: text)
    }

    /// The braced body opening at or after `start`, without its outer braces.
    private static func body(from start: String.Index, in text: String) -> Substring? {
        guard let open = text[start...].firstIndex(of: "{") else { return nil }
        var depth = 0
        for index in text[open...].indices {
            switch text[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return text[text.index(after: open)..<index] }
            default: continue
            }
        }
        return nil
    }
}
