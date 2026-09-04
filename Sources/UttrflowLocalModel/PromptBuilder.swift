import UttrflowPredict

/// Lays one moment out for the model under a fixed budget, trimming the context before ever touching the line.
enum PromptBuilder {
    /// About 700 tokens of Gemma's vocabulary, which keeps the prefill to a fraction of the pass.
    static let budgetInCharacters = 2_400

    /// The whole message: where the caret is, the register, what is around it, how this person writes here, the line.
    static func message(typed: String, in situation: GenerationSituation, register: Register) -> String {
        var located = "application \(situation.application)"
        if let title = situation.windowTitle { located += ", window \"\(title)\"" }
        if let field = situation.field { located += ", field \(field)" }
        if let document = situation.document { located += ", document \(document)" }
        let opening = "In \(located).\nHints: \(register.hints.joined(separator: "; "))."
        let closing = "Continue this line:\n\(typed)"

        // What is fixed is paid for first; the context gets whatever is left, farthest from the line trimmed first.
        var remaining = budgetInCharacters - opening.count - closing.count
        var parts = [opening]
        let preceding = situation.preceding.map { Self.tail($0, within: remaining / 2) }
        remaining -= preceding.map { $0.count + 40 } ?? 0
        let recent = Self.newest(situation.recentLines, within: remaining / 2)
        remaining -= recent.isEmpty ? 0 : recent.joined(separator: "\n").count + 40
        let surroundings = situation.surroundings.map { Self.tail($0, within: remaining) }

        if let surroundings, !surroundings.isEmpty {
            parts.append("On screen around the field:\n\(surroundings)")
        }
        if !recent.isEmpty {
            parts.append("Lines this person wrote here before:\n" + recent.joined(separator: "\n"))
        }
        if let preceding, !preceding.isEmpty {
            parts.append("The text before the line reads:\n\(preceding)")
        }
        parts.append(closing)
        return parts.joined(separator: "\n\n")
    }

    /// The end of the text, which is the part nearest the line, cut to the allowance.
    static func tail(_ text: String, within allowance: Int) -> String {
        guard allowance > 0 else { return "" }
        return text.count > allowance ? String(text.suffix(allowance)) : text
    }

    /// The newest lines that fit the allowance, oldest dropped first, since newest is how the person writes now.
    static func newest(_ lines: [String], within allowance: Int) -> [String] {
        var kept: [String] = []
        var used = 0
        for line in lines {
            guard used + line.count + 1 <= allowance else { break }
            kept.append(line)
            used += line.count + 1
        }
        return kept
    }
}
