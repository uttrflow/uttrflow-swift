import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// Words the screen, the person and the field might hold, none of them a heading of the prompt's own.
private let words = [
    "Priya", "are", "you", "coming", "tonight", "on", "my", "way", "git", "commit", "ls", "-la", "kal",
    "milenge",
    "release", "notes", "🙏", "नमस्ते", "the", "quick", "brown", "fox", "2026-09-14", "#1873", "4.2.1", "Reply",
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
        "The context around the line never takes more than its token budget, whatever the size of the input.",
        arguments: moments)
    func theBudgetHolds(moment: PromptCase) {
        let prompt = moment.prompt
        // The opening runs to the first blank line and the closing from the last one before the ask.
        guard let openingEnd = prompt.range(of: "\n\n"),
            let closingStart =
                prompt.range(of: "\n\nContinue this ", options: .backwards)
                ?? prompt.range(of: "\n\nGive up to three", options: .backwards)
        else {
            Issue.record("the prompt has no opening or no closing")
            return
        }
        let opening = String(prompt[..<openingEnd.lowerBound])
        let closing = String(prompt[prompt.index(closingStart.lowerBound, offsetBy: 2)...])
        let context =
            openingEnd.upperBound < closingStart.lowerBound
            ? String(prompt[openingEnd.upperBound..<closingStart.lowerBound]) : ""
        #expect(PromptBuilder.estimatedTokens(context) <= PromptBuilder.contextBudgetInTokens)
        #expect(
            PromptBuilder.estimatedTokens(prompt)
                <= PromptBuilder.estimatedTokens(opening) + PromptBuilder.estimatedTokens(closing)
                + PromptBuilder.contextBudgetInTokens + 4)
        if let screen = section(onScreen, in: prompt) {
            #expect(PromptBuilder.estimatedTokens(onScreen + screen) <= PromptBuilder.screenBudgetInTokens)
        }
    }

    @Test(
        "The text nearest the caret is what is kept: the end of the field's own text, and the screen's nearest line.",
        arguments: moments)
    func theCaretNearTextIsKept(moment: PromptCase) {
        let prompt = moment.prompt
        let preceding = moment.situation.preceding ?? ""
        if !preceding.isEmpty {
            let kept = section(textBefore, in: prompt) ?? ""
            #expect(!kept.isEmpty && preceding.hasSuffix(kept))
            #expect(kept.last == preceding.last)
        }
        let nearest = moment.situation.surroundings?.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
        let ownTextSuffices =
            PromptBuilder.estimatedTokens(section(textBefore, in: prompt) ?? "")
            >= PromptBuilder.ownTextSufficesInTokens
        if let nearest, !ownTextSuffices {
            let lastShown = section(onScreen, in: prompt)?.split(separator: "\n").last.map(String.init)
            #expect(lastShown.map { !$0.isEmpty && nearest.hasSuffix($0) } == true)
        }
        if ownTextSuffices { #expect(section(onScreen, in: prompt) == nil) }
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
                    PromptBuilder.instruction(for: moment.register) + ":\n" + moment.typed))
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
            // Every line shown is a line of the screen, said once, in the screen's own order.
            let lines = screen.split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let shown = kept.split(separator: "\n").map(String.init)
            #expect(Set(shown).count == shown.count)
            var from = lines.startIndex
            for line in shown.dropFirst() {
                guard let at = lines[from...].firstIndex(of: line) else {
                    Issue.record("a shown line is not a line of the screen")
                    break
                }
                from = lines.index(after: at)
            }
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
        "The tail is the longest end and the newest lines the most that fit a token allowance, never more.",
        arguments: 0..<300)
    func tailAndNewestKeepToTheAllowance(seed: Int) {
        var random = Seeded(seed: seed)
        let text = (0..<Int.random(in: 0...30, using: &random)).map { _ in random.pick(words) }
            .joined(separator: random.chance(0.5) ? " " : "\n")
        let allowance = Int.random(in: -5...40, using: &random)
        let tail = PromptBuilder.tail(text, within: allowance)
        #expect(text.hasSuffix(tail))
        #expect(PromptBuilder.estimatedTokens(tail) <= max(allowance, 0))
        if tail.count < text.count, allowance > 0 {
            #expect(PromptBuilder.estimatedTokens(String(text.suffix(tail.count + 1))) > allowance)
        }
        let head = PromptBuilder.head(text, within: allowance)
        #expect(text.hasPrefix(head))
        #expect(head.count == min(text.count, max(allowance, 0)))
        let lines = (0..<Int.random(in: 0...10, using: &random)).map { _ in
            (0..<Int.random(in: 1...6, using: &random)).map { _ in random.pick(words) }.joined(separator: " ")
        }
        let kept = PromptBuilder.newest(lines, within: allowance)
        // The newest line is kept cut down only when it alone overflows.
        if kept.count == 1, kept[0] != lines[0] {
            #expect(lines[0].hasPrefix(kept[0]))
        } else {
            #expect(Array(lines.prefix(kept.count)) == kept)
        }
        let used = kept.reduce(0) { $0 + PromptBuilder.estimatedTokens($1) + 1 }
        #expect(used <= max(allowance, 0))
        let screen = PromptBuilder.nearestLines(lines.reversed().joined(separator: "\n"), within: allowance)
        #expect(PromptBuilder.estimatedTokens(screen) <= max(allowance, 0))
    }

    @Test("The estimate only grows as text is added to either end.", arguments: 0..<200)
    func theEstimateIsMonotone(seed: Int) {
        var random = Seeded(seed: seed)
        let text = (0..<Int.random(in: 1...20, using: &random)).map { _ in random.pick(words) }
            .joined(separator: random.pick([" ", "  ", "\n", ", "]))
        let characters = Array(text)
        for cut in 0..<characters.count {
            #expect(
                PromptBuilder.estimatedTokens(String(characters[cut...]))
                    >= PromptBuilder.estimatedTokens(String(characters[(cut + 1)...])))
            #expect(
                PromptBuilder.estimatedTokens(String(characters[...cut]))
                    >= PromptBuilder.estimatedTokens(String(characters[..<cut])))
        }
    }
}
