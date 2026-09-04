import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// Words the screen, the person and the field might hold, none of them a heading of the prompt's own.
private let words = [
    "Priya", "are", "you", "coming", "tonight", "on", "my", "way", "git", "commit", "ls", "-la", "kal",
    "milenge",
    "release", "notes", "🙏", "नमस्ते", "the", "quick", "brown", "fox",
]

private let onScreen = "On screen around the field:\n"
private let wroteHere = "Lines this person wrote here before:\n"
private let textBefore = "The text before the line reads:\n"

/// One moment built from a seed, with parts of every length up to thousands of characters.
struct PromptCase: Sendable, CustomTestStringConvertible {
    let seed: Int
    let situation: GenerationSituation
    let register: Register
    let typed: String
    let ask: Ask

    init(seed: Int) {
        var random = Seeded(seed: seed)
        self.seed = seed
        situation = GenerationSituation(
            application: random.pick(["Terminal", "Chat", "Notes", "Safari"]),
            field: random.chance(0.5) ? random.pick(["Message", "AXTextArea", "Search"]) : nil,
            document: random.chance(0.5) ? random.pick(["Ideas", "example.com", "~/src"]) : nil,
            preceding: random.chance(0.7) ? PromptCase.text(&random, upTo: 5_000) : nil,
            windowTitle: random.chance(0.5) ? random.pick(["Priya", "Untitled", "zsh"]) : nil,
            surroundings: random.chance(0.7) ? PromptCase.text(&random, upTo: 5_000) : nil,
            recentLines: (0..<Int.random(in: 0...60, using: &random)).map { _ in
                PromptCase.text(&random, upTo: random.chance(0.1) ? 600 : 80, lines: 1)
            },
            isMultiline: random.chance(0.5))
        register = Register(
            isMultiline: random.chance(0.5),
            typicalLength: random.chance(0.5) ? nil : Int.random(in: 1...400, using: &random),
            isConversational: random.chance(0.5), symbolShare: Double.random(in: 0...0.3, using: &random),
            usesSentenceCase: random.pick([nil, true, false]))
        typed = PromptCase.text(&random, upTo: random.chance(0.15) ? 5_000 : 200, lines: 1)
        ask = random.chance(0.3) ? .others(excluding: PromptCase.text(&random, upTo: 60, lines: 1)) : .one
    }

    var testDescription: String { "seed \(seed)" }

    var prompt: String { PromptBuilder.message(typed: typed, in: situation, register: register, asking: ask) }

    /// Text of some length up to the bound, on lines of forty characters or so, with no blank line anywhere.
    private static func text(_ random: inout Seeded, upTo bound: Int, lines: Int? = nil) -> String {
        let length = Int.random(in: 1...bound, using: &random)
        var text = ""
        while text.count < length {
            text += random.pick(words)
            text += lines == 1 || !random.chance(0.15) ? " " : "\n"
        }
        return String(text.prefix(length)).replacingOccurrences(of: "\n", with: lines == 1 ? " " : "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "end"
    }
}

private let moments = (0..<300).map(PromptCase.init)

/// The section under a heading, up to the blank line that ends it, or nothing when the heading is absent.
private func section(_ heading: String, in prompt: String) -> String? {
    guard let start = prompt.range(of: heading)?.upperBound else { return nil }
    let rest = prompt[start...]
    return String(rest[..<(rest.range(of: "\n\n")?.lowerBound ?? rest.endIndex)])
}

@Suite("The generation prompt, over random moments")
struct PromptPropertyTests {
    @Test(
        "The message stays within the budget and a little slack, unless the fixed parts alone exceed it.",
        arguments: moments)
    func theBudgetHolds(moment: PromptCase) {
        let prompt = moment.prompt
        // The opening runs to the first blank line and the closing from the last one before the ask.
        let opening = prompt.range(of: "\n\n").map { prompt[..<$0.lowerBound].count } ?? 0
        let closing =
            (prompt.range(of: "\n\nContinue this ", options: .backwards)
            ?? prompt.range(of: "\n\nGive up to three", options: .backwards))
            .map { prompt[$0.lowerBound...].count - 2 } ?? 0
        #expect(opening > 0 && closing > 0)
        let fixed = opening + closing
        #expect(prompt.count <= max(PromptBuilder.budgetInCharacters, fixed) + 110)
        if moment.typed.count <= 600 { #expect(prompt.count <= PromptBuilder.budgetInCharacters + 110) }
    }

    @Test(
        "The message always ends with the ask and the typed text, untouched however long it is.",
        arguments: moments)
    func theLineIsNeverTouched(moment: PromptCase) {
        let prompt = moment.prompt
        switch moment.ask {
        case .one:
            #expect(
                prompt.hasSuffix(
                    "Continue this \(moment.register.kind) with the single most likely completion, on one line:\n"
                        + moment.typed))
        case .others(let leader):
            #expect(prompt.contains("each different from \"\(leader)\", one per line:\n" + moment.typed))
            #expect(prompt.hasSuffix("one per line:\n" + moment.typed))
        }
        #expect(prompt.hasPrefix("In application \(moment.situation.application)"))
        #expect(prompt.contains("\nHints: " + moment.register.hints.joined(separator: "; ") + "."))
    }

    @Test("A heading appears exactly when its part is present, and never twice.", arguments: moments)
    func headingsMatchTheirParts(moment: PromptCase) {
        let prompt = moment.prompt
        for (heading, present) in [
            (onScreen, moment.situation.surroundings != nil),
            (wroteHere, !moment.situation.recentLines.isEmpty),
            (textBefore, moment.situation.preceding != nil),
        ] {
            let count = prompt.components(separatedBy: heading).count - 1
            #expect(count <= 1)
            if count == 1 { #expect(present) }
            if !present { #expect(count == 0) }
        }
    }

    @Test(
        "Each part kept is the end of its text or the newest of its lines, and only ever shrinks.",
        arguments: moments)
    func partsKeepTheirNearestEnd(moment: PromptCase) {
        let prompt = moment.prompt
        if let kept = section(onScreen, in: prompt), let screen = moment.situation.surroundings {
            #expect(screen.hasSuffix(kept))
        }
        if let kept = section(textBefore, in: prompt), let preceding = moment.situation.preceding {
            #expect(preceding.hasSuffix(kept))
        }
        if let kept = section(wroteHere, in: prompt) {
            let lines = kept.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let recent = moment.situation.recentLines
            // The newest line alone may be cut down when even it does not fit; every other kept line is whole.
            if lines.count == 1, lines[0] != recent.first {
                #expect(recent.first?.hasPrefix(lines[0]) == true)
            } else {
                #expect(Array(recent.prefix(lines.count)) == lines)
            }
        }
    }

    @Test(
        "The screen is trimmed before the person's lines, and those before the text before the line.",
        arguments: moments)
    func trimmingStartsFarthestFromTheLine(moment: PromptCase) {
        let situation = moment.situation
        let prompt = moment.prompt
        // The earlier text is cut the same whether or not the screen and the person's lines are there to compete.
        let alone = GenerationSituation(
            application: situation.application, field: situation.field, document: situation.document,
            preceding: situation.preceding, windowTitle: situation.windowTitle,
            isMultiline: situation.isMultiline)
        let promptAlone = PromptBuilder.message(
            typed: moment.typed, in: alone, register: moment.register, asking: moment.ask)
        #expect(section(textBefore, in: prompt) == section(textBefore, in: promptAlone))
        // The person's lines are cut the same whether or not the screen is there to compete.
        let unseen = GenerationSituation(
            application: situation.application, field: situation.field, document: situation.document,
            preceding: situation.preceding, windowTitle: situation.windowTitle,
            recentLines: situation.recentLines,
            isMultiline: situation.isMultiline)
        let promptUnseen = PromptBuilder.message(
            typed: moment.typed, in: unseen, register: moment.register, asking: moment.ask)
        #expect(section(wroteHere, in: prompt) == section(wroteHere, in: promptUnseen))
        #expect(section(textBefore, in: prompt) == section(textBefore, in: promptUnseen))
    }

    @Test(
        "The tail is a suffix and the head a prefix no longer than the allowance, and the newest lines fill it without overflowing.",
        arguments: 0..<300)
    func tailAndNewestKeepToTheAllowance(seed: Int) {
        var random = Seeded(seed: seed)
        let text = String(repeating: "x", count: Int.random(in: 0...50, using: &random))
        let allowance = Int.random(in: -5...60, using: &random)
        let tail = PromptBuilder.tail(text, within: allowance)
        #expect(text.hasSuffix(tail))
        #expect(tail.count <= max(allowance, 0))
        #expect(tail.count == min(text.count, max(allowance, 0)))
        let head = PromptBuilder.head(text, within: allowance)
        #expect(text.hasPrefix(head))
        #expect(head.count == min(text.count, max(allowance, 0)))
        let lines = (0..<Int.random(in: 0...10, using: &random)).map { _ in
            String(repeating: "l", count: Int.random(in: 0...12, using: &random))
        }
        let kept = PromptBuilder.newest(lines, within: allowance)
        // The newest line is kept cut down only when it alone overflows, and then it fills the allowance exactly.
        if kept.count == 1, kept[0] != lines[0] {
            #expect(lines[0].hasPrefix(kept[0]))
            #expect(kept[0].count == allowance - 1)
        } else {
            #expect(Array(lines.prefix(kept.count)) == kept)
        }
        let used = kept.reduce(0) { $0 + $1.count + 1 }
        #expect(used <= max(allowance, 0))
        if kept.count < lines.count { #expect(used + lines[kept.count].count + 1 > allowance) }
    }
}
