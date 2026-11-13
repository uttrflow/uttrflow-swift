// Dictation read with a persona's words off, on and wrong, to show the gain and the harm of conditioning on them.
import Foundation
package import UttrflowCore

/// An invented persona: the names of tools, projects and people one person's dictation holds.
package struct Persona: Sendable, Equatable {
    package let id: String
    package let terms: [String]
}

/// One invented sentence a persona dictates, holding some of its terms.
package struct PersonaDictation: Sendable, Equatable {
    package let persona: String
    package let sentence: String
    package let terms: [String]
}

/// What the recogniser is handed before it decodes a clip.
package enum PersonaCondition: String, CaseIterable, Sendable {
    /// No persona words at all.
    case off
    /// The words of the persona that dictated the clip.
    case on
    /// The words of another persona, which a persona feature must not let hurt.
    case wrong
}

/// The corpus, read from `Resources/Corpus/Personas/personas.json`: three personas, each dictating the same number of sentences.
package enum PersonaCorpus {
    private struct Record: Decodable {
        let kind: String
        let persona: String
        let sentence: String?
        let terms: [String]
    }

    private static let records: [Record] =
        Bundle.module.path(forResource: "personas", ofType: "json", inDirectory: "Corpus/Personas")
        .flatMap { FileManager.default.contents(atPath: $0) }
        .flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []

    package static var personas: [Persona] {
        records.filter { $0.kind == "persona" }.map { Persona(id: $0.persona, terms: $0.terms) }
    }

    package static var items: [PersonaDictation] {
        records.compactMap { record in
            record.sentence.map {
                PersonaDictation(persona: record.persona, sentence: $0, terms: record.terms)
            }
        }
    }

    /// The words `condition` hands over for an item: its persona's, the next persona's, or none.
    package static func vocabulary(for item: PersonaDictation, under condition: PersonaCondition) -> [String]
    {
        guard let index = personas.firstIndex(where: { $0.id == item.persona }) else { return [] }
        switch condition {
        case .off: return []
        case .on: return personas[index].terms
        case .wrong: return personas[(index + 1) % personas.count].terms
        }
    }
}

/// One clip decoded under one condition.
package struct PersonaRow: Sendable, Equatable {
    package let item: PersonaDictation
    package let condition: PersonaCondition
    package let transcript: String

    package init(item: PersonaDictation, condition: PersonaCondition, transcript: String) {
        self.item = item
        self.condition = condition
        self.transcript = transcript
    }

    /// How many of the item's terms the transcript holds, whatever their case.
    package var termsHeard: Int {
        let words = Set(TailCommit.scoredWords(transcript))
        return item.terms.count { words.contains(TailCommit.normalized($0)) }
    }

    package var wordErrors: WordErrorRate {
        TailCommit.wordErrorRate(hypothesis: transcript, reference: item.sentence)
    }
}

/// The rows summed per persona and condition, with the gain from the right words, the harm from the wrong ones and the verdict on the harm.
package struct PersonaReport: Sendable {
    package let rows: [PersonaRow]

    /// The most the wrong persona's words may add to a persona's word error rate over no words at all, in points of the rate.
    package static let harmLimit = 0.02

    package init(rows: [PersonaRow]) { self.rows = rows }

    private func errorRate(_ persona: String, _ condition: PersonaCondition) -> Double? {
        let group = rows.filter { $0.item.persona == persona && $0.condition == condition }
        let words = group.reduce(0) { $0 + $1.wordErrors.referenceWordCount }
        guard words > 0 else { return nil }
        return Double(group.reduce(0) { $0 + $1.wordErrors.errors }) / Double(words)
    }

    /// Points of word error rate the persona's own words removed; positive is a gain.
    package func gain(of persona: String) -> Double? {
        guard let off = errorRate(persona, .off), let on = errorRate(persona, .on) else { return nil }
        return off - on
    }

    /// Points of word error rate another persona's words added; positive is harm.
    package func harm(to persona: String) -> Double? {
        guard let off = errorRate(persona, .off), let wrong = errorRate(persona, .wrong) else { return nil }
        return wrong - off
    }

    /// The personas whose harm is over the limit.
    package var harmed: [String] {
        Set(rows.map(\.item.persona)).sorted().filter { (harm(to: $0) ?? 0) > Self.harmLimit }
    }

    /// One line per persona and condition, then the gain and harm per persona and the verdict.
    package var markdown: String {
        var lines = [
            "| Persona | Words | Clips | Terms heard | Word error rate |",
            "|---|---|---|---|---|",
        ]
        let personas = Array(Set(rows.map(\.item.persona))).sorted()
        for persona in personas {
            for condition in PersonaCondition.allCases {
                let group = rows.filter { $0.item.persona == persona && $0.condition == condition }
                guard !group.isEmpty, let rate = errorRate(persona, condition) else { continue }
                let heard = group.reduce(0) { $0 + $1.termsHeard }
                let terms = group.reduce(0) { $0 + $1.item.terms.count }
                lines.append(
                    "| \(persona) | \(condition.rawValue) | \(group.count) | \(heard)/\(terms) | \(Self.percent(rate)) |"
                )
            }
        }
        lines += ["", "| Persona | Gain from its own words | Harm from another's |", "|---|---|---|"]
        for persona in personas {
            lines.append(
                "| \(persona) | \(Self.points(gain(of: persona))) | \(Self.points(harm(to: persona))) |")
        }
        let verdict =
            harmed.isEmpty
            ? "Harm within the limit of \(Self.points(Self.harmLimit))."
            : "FAIL: harm over \(Self.points(Self.harmLimit)) for \(harmed.joined(separator: ", "))."
        return (lines + ["", verdict]).joined(separator: "\n")
    }

    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
    private static func points(_ value: Double?) -> String {
        value.map { String(format: "%+.1f points", $0 * 100) } ?? "none"
    }
}
