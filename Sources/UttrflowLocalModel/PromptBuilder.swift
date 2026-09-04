import UttrflowPredict

/// What one pass asks the model for: the one line the person waits for, or the others behind it.
enum Ask: Equatable, Sendable {
    /// The single most likely way to finish the line, on one line.
    case one
    /// Up to three other ways, none of them the line already on screen.
    case others(excluding: String)

    /// The decoded text that ends the pass: the newline after one line, or nothing when several lines are wanted.
    var stopStrings: Set<String>? { self == .one ? ["\n"] : nil }
}

/// Lays one moment out for the model under a fixed budget, trimming the context before ever touching the line.
enum PromptBuilder {
    /// About 400 tokens of Gemma's vocabulary; prefilling the moment's context is the bulk of a pass, so this is the lever.
    static let budgetInCharacters = 1_400

    /// A window title, field name or document longer than this names nothing more, and the rest is the context's.
    static let locatorCap = 80

    /// What a heading and the blank lines around it add to a part of the context.
    static let headingCost = 40

    /// The whole message: where the caret is, the register, what is around it, how this person writes here, the line.
    static func message(
        typed: String, in situation: GenerationSituation, register: Register, asking ask: Ask = .one
    ) -> String {
        var located = "application \(situation.application)"
        if let title = situation.windowTitle {
            located += ", window \"\(Self.head(title, within: locatorCap))\""
        }
        if let field = situation.field { located += ", field \(Self.head(field, within: locatorCap))" }
        if let document = situation.document {
            located += ", document \(Self.head(document, within: locatorCap))"
        }
        let opening = "In \(located).\nHints: \(register.hints.joined(separator: "; "))."
        let closing =
            switch ask {
            case .one:
                "Continue this line with the single most likely completion, on one line:\n\(typed)"
            case .others(let leader):
                "Give up to three other ways to finish this line, each different from \"\(leader)\", "
                    + "one per line:\n\(typed)"
            }

        // What is fixed is paid for first; the context gets whatever is left, farthest from the line trimmed first.
        var remaining = budgetInCharacters - opening.count - closing.count
        var parts = [opening]
        let preceding = situation.preceding.map { Self.tail($0, within: remaining / 2) } ?? ""
        remaining -= Self.cost(of: preceding)
        let recent = Self.newest(situation.recentLines, within: remaining / 2).joined(separator: "\n")
        remaining -= Self.cost(of: recent)
        let surroundings = situation.surroundings.map { Self.tail($0, within: remaining) } ?? ""

        if !surroundings.isEmpty {
            parts.append("On screen around the field:\n\(surroundings)")
        }
        if !recent.isEmpty {
            parts.append("Lines this person wrote here before:\n\(recent)")
        }
        if !preceding.isEmpty {
            parts.append("The text before the line reads:\n\(preceding)")
        }
        parts.append(closing)
        return parts.joined(separator: "\n\n")
    }

    /// What a part takes from the budget: its text and its heading, or nothing once it has trimmed to nothing.
    private static func cost(of part: String) -> Int {
        part.isEmpty ? 0 : part.count + headingCost
    }

    /// The start of the text, which is where a title or a name says what it is, cut to the allowance.
    static func head(_ text: String, within allowance: Int) -> String {
        guard allowance > 0 else { return "" }
        return text.count > allowance ? String(text.prefix(allowance)) : text
    }

    /// The end of the text, which is the part nearest the line, cut to the allowance.
    static func tail(_ text: String, within allowance: Int) -> String {
        guard allowance > 0 else { return "" }
        return text.count > allowance ? String(text.suffix(allowance)) : text
    }

    /// The newest lines that fit the allowance, oldest dropped first, and the newest alone cut down when even it does not fit.
    static func newest(_ lines: [String], within allowance: Int) -> [String] {
        var kept: [String] = []
        var used = 0
        for line in lines {
            guard used + line.count + 1 <= allowance else { break }
            kept.append(line)
            used += line.count + 1
        }
        if kept.isEmpty, let first = lines.first, allowance > 1 {
            return [Self.head(first, within: allowance - 1)]
        }
        return kept
    }
}
