import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Holds every refusal the guard can reach to being reproduced in both directions, or to saying in one place why it has no mirror.
@Suite("Every meaning check reads both ways")
struct GuardMirrorTests {
    /// The guard under test.
    private let sut = MeaningPreservationGuard()

    /// An edit and the same edit inverted; a check that reads one way refuses one of the pair and lets the other through.
    static let mirroredEdits: [(arm: String, kept: String, rewritten: String)] = [
        ("a content word", "we should ship the build on Friday", "We should the build on Friday."),
        ("a negation", "we should ship this on Friday", "We should not ship this on Friday."),
        ("a number said in words", "i need chairs", "I need twenty chairs."),
        ("the bulk of the words", "the quarterly report is late again and the client noticed", "Late."),
        ("every word", "hello there", ""),
    ]

    /// Refusals with no mirror, each saying why; a reason may leave this list, and a new one may never join it.
    static let unmirrored: [String: String] = [
        "the rewrite begins with":
            "a preamble is the model chatting, and a speaker who opens with one is owed their words",
        "the rewrite read":
            "the readings offered are one-sided by construction, and the half that mattered is the invention arm",
        "the rewrite dropped a line break the speaker asked for":
            "an added break is the passes' to settle, per Docs/cleanup-design.md:272",
        "the rewrite changed":
            "the churn allowance is set by the produced side, which PLAN.md records as a corpus measurement still owed",
    ]

    /// The reason the guard gives, or nil where it accepted.
    private func refusal(_ kept: String, _ rewritten: String) -> String? {
        guard case .rejected(let reason) = sut.verdict(draft: Draft(text: kept), rewritten: rewritten)
        else { return nil }
        return reason
    }

    @Test("refuses an edit and the same edit inverted", arguments: mirroredEdits)
    func refusesBothDirections(edit: (arm: String, kept: String, rewritten: String)) {
        #expect(refusal(edit.kept, edit.rewritten) != nil, "\(edit.arm) removed is not refused")
        #expect(refusal(edit.rewritten, edit.kept) != nil, "\(edit.arm) added is not refused")
    }

    /// The stable head of every `reason:` literal in the guard, cut before the first interpolation.
    static func reasonPrefixes() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/UttrflowAI/MeaningPreservationGuard.swift"),
            encoding: .utf8)
        var prefixes: Set<String> = []
        for piece in source.components(separatedBy: "reason: \"").dropFirst() {
            let literal = String(piece.prefix { $0 != "\"" }).components(separatedBy: "\\(")[0]
            let head = literal.trimmingCharacters(in: CharacterSet(charactersIn: " '"))
            if !head.isEmpty { prefixes.insert(head) }
        }
        return prefixes
    }

    @Test("reaches every refusal the guard can give from both sides, or records why it cannot")
    func everyRefusalIsMirroredOrRecorded() throws {
        let produced = Set(
            Self.mirroredEdits.flatMap { [refusal($0.kept, $0.rewritten), refusal($0.rewritten, $0.kept)] }
                .compactMap { $0 })
        let prefixes = try Self.reasonPrefixes()
        #expect(prefixes.count > 1, "no reason literals were read from the guard's source")
        for prefix in prefixes {
            let isMirrored = produced.contains { $0.hasPrefix(prefix) }
            let recorded = Self.unmirrored[prefix] != nil
            #expect(
                isMirrored != recorded,
                isMirrored
                    ? "\"\(prefix)\" is reached both ways now: take it out of unmirrored"
                    : "\"\(prefix)\" is reached one way only: mirror it, or record in unmirrored why it has none"
            )
        }
        for prefix in Self.unmirrored.keys where !prefixes.contains(prefix) {
            Issue.record("\"\(prefix)\" is no longer a reason the guard gives: take it out of unmirrored")
        }
    }
}
