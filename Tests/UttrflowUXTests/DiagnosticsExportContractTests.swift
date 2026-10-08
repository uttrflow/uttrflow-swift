// Tests that every field of the diagnostics snapshot is listed in its contract, and that every text it holds is classified.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("The diagnostics export contract covers every snapshot field")
struct DiagnosticsExportContractTests {
    /// Where a text value inside the snapshot may go when the report is copied.
    enum TextUse {
        /// A build, macOS build or model revision string, printed as is.
        case version
        /// An engine or clean-up step name chosen by the app, never by the speaker.
        case appName
        /// Dictated, kept or offered words; the report counts them or drops them.
        case neverPrinted
    }

    /// Every text path a snapshot can hold. A new text field fails the walk until it is classified here.
    static let textPaths: [String: TextUse] = [
        "version.short": .version,
        "version.build": .version,
        "machine": .version,
        "speechModelLoads.systemBuild": .version,
        "speechModelLoads.modelRevision": .version,
        "cleaning.refusals.engine": .appName,
        "cleaning.changes.step.rawValue": .appName,
        "vocabularyPrompt": .neverPrinted,
        "cleaning.changes.removed": .neverPrinted,
        "cleaning.changes.replaced.from": .neverPrinted,
        "cleaning.changes.replaced.to": .neverPrinted,
        "cleaning.changes.inserted": .neverPrinted,
        "cleaning.refusals.reason": .neverPrinted,
    ]

    /// The redaction snapshot with every other text-bearing field filled too.
    static func populated() -> DiagnosticsSnapshot {
        let base = DiagnosticsReportRedactionTests.snapshot()
        let load = SpeechModelLoadRecord(
            date: Date(timeIntervalSince1970: 0), seconds: 1, parts: nil, systemBuild: "25A1",
            modelRevision: "abc1234", change: .unchanged, isLikelyRecompile: false)
        return DiagnosticsSnapshot(
            vocabularyPrompt: base.vocabularyPrompt, speechModelLoads: [load],
            cleaning: base.cleaning, lastCleanedBy: base.lastCleanedBy,
            version: AppVersion(short: "1.0", build: "1"), machine: "macOS 26.0, example chip, 16 GB")
    }

    /// The dotted field path of every `String` reachable from `value`, with collection positions left out.
    static func textPaths(in value: Any, at path: [String] = []) -> Set<String> {
        if value is String { return [path.joined(separator: ".")] }
        let mirror = Mirror(reflecting: value)
        var found: Set<String> = []
        for child in mirror.children {
            let isPosition =
                mirror.displayStyle == .collection || mirror.displayStyle == .set
                || mirror.displayStyle == .optional || mirror.displayStyle == .dictionary
                || mirror.displayStyle == .tuple
            let next = isPosition || child.label == nil ? path : path + [child.label ?? ""]
            found.formUnion(textPaths(in: child.value, at: next))
        }
        return found
    }

    @Test("every text inside a filled snapshot is classified")
    func everyTextIsClassified() {
        let found = Self.textPaths(in: Self.populated())
        let unclassified = found.subtracting(Self.textPaths.keys)
        #expect(
            unclassified.isEmpty, "classify these in DiagnosticsExportContractTests: \(unclassified.sorted())"
        )
        let unreached = Set(Self.textPaths.keys).subtracting(found)
        #expect(unreached.isEmpty, "the filled snapshot no longer reaches \(unreached.sorted())")
    }

    @Test("the field table in Docs/diagnostics-export.md names every snapshot field")
    func tableMatchesType() throws {
        let fields = Set(Mirror(reflecting: DiagnosticsSnapshot()).children.compactMap(\.label))
        let doc = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Docs/diagnostics-export.md")
        let rows = try String(contentsOf: doc, encoding: .utf8).split(separator: "\n")
            .filter { $0.hasPrefix("| `") }
            .map { $0.split(separator: "|", omittingEmptySubsequences: true).first ?? "" }
        let named = Set(
            rows.flatMap {
                $0.split(separator: "`").enumerated()
                    .filter { $0.offset % 2 == 1 }.map { String($0.element) }
            })
        #expect(
            fields == named,
            "missing from the table: \(fields.subtracting(named).sorted()); not fields: \(named.subtracting(fields).sorted())"
        )
    }
}
