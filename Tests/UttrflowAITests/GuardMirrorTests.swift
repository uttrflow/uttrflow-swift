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
        (
            "a word's place", "we approved the design but rejected the budget",
            "We rejected the design but approved the budget."
        ),
    ]

    /// Refusals with no mirror, each saying why; a reason may leave this list, and a new one may never join it.
    static let unmirrored: [String: String] = [
        "the rewrite begins with":
            "a preamble is the model chatting, and a speaker who opens with one is owed their words",
        "the rewrite read":
            "the readings offered are one-sided by construction, and the half that mattered is the invention arm",
        "the rewrite dropped a line break the speaker asked for":
            "an added break is the passes' to settle, per the guard section of Docs/cleanup-design.md",
        "the rewrite wrote":
            "an amount is refused whichever way the symbol moved, so the pair is one check rather than two arms",
        "the rewrite changed":
            "the churn allowance is set by the produced side, as Docs/ai-model-output.md records",
        "the rewrite composed a list the speaker did not speak":
            "a list taken away is a dropped break, which the check above already refuses; composing one is the arm Tier 3 names",
        "the rewrite added a line break the speaker did not ask for":
            "the mirror of this is the dropped-break refusal above, and both are asked of the destination's layout rather than of the text alone",
        "the rewrite moved a negation":
            "negation placement is directional only when both sides retain the same plain-text negator count",
        "the rewrite added an exclamation mark":
            "a mark the speaker did not say is refused; one they said and the rewrite dropped is a spoken punctuation refusal",
        "the rewrite added quotation marks":
            "the same: quotes added are this check, quotes dropped are the spoken punctuation one",
        "the rewrite changed a kept word's form":
            "asked only of an as-spoken destination, and a form changed back is the same change",
        "the rewrite changed a spoken ampersand":
            "the spoken word and the mark are one check either way, so the pair is one check rather than two arms",
        "the rewrite changed the Indian grouping in":
            "grouping is the destination's number style, set on the produced side",
        "the rewrite changed the capitalization of":
            "a capital the speaker gave is kept; one the rewrite gives a sentence opening is the formatter's",
        "the rewrite dropped a spoken punctuation mark":
            "the marks are written by a pass from spoken words, so only the draft side can hold one",
        "the rewrite dropped the apostrophe in":
            "restoring an apostrophe is a listed repair in Docs/cleanup.md, so only dropping one is refused",
        "the rewrite moved a word":
            "a function word swapped back is the same move, and a content word moved is named by the survival check",
        "the rewrite of a long text ends no sentence":
            "punctuation is the rewrite's to add, so only the produced side can lack it",
        "the rewrite replaced high-confidence":
            "recogniser confidence exists only on the draft side",
    ]

    /// The reason the guard gives, or nil where it accepted.
    private func refusal(_ kept: String, _ rewritten: String) -> String? {
        guard case .rejected(let reason, _) = sut.verdict(draft: Draft(text: kept), rewritten: rewritten)
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
        // The guard is split across extensions by what each decides, so every file of it is read.
        let directory = root.appendingPathComponent("Sources/UttrflowAI")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter {
                $0 == "MeaningPreservationGuard.swift" || ($0.hasPrefix("Guard") && $0.hasSuffix(".swift"))
            }
        let source = try files.map {
            try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")
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
