import Testing

@testable import UttrflowEval

@Suite("Persona evaluation: the gain from a persona's words and the harm from another's")
struct PersonaEvaluationTests {
    private static let item = PersonaItem(
        persona: "developer", sentence: "ask Marlowen about Quorvex", terms: ["Marlowen", "Quorvex"])

    private static func row(
        _ condition: PersonaCondition, _ transcript: String, _ item: PersonaItem = item
    )
        -> PersonaRow
    {
        PersonaRow(item: item, condition: condition, transcript: transcript)
    }

    @Test("each condition hands over its own words: none, the persona's, the next persona's")
    func vocabulary() {
        let item = PersonaCorpus.items[0]
        #expect(PersonaCorpus.vocabulary(for: item, under: .off).isEmpty)
        #expect(PersonaCorpus.vocabulary(for: item, under: .on) == PersonaCorpus.personas[0].terms)
        #expect(PersonaCorpus.vocabulary(for: item, under: .wrong) == PersonaCorpus.personas[1].terms)
        let last = PersonaCorpus.items.last!
        #expect(PersonaCorpus.vocabulary(for: last, under: .wrong) == PersonaCorpus.personas[0].terms)
    }

    @Test("the corpus gives every persona the same number of sentences, each holding its own terms")
    func corpus() {
        for persona in PersonaCorpus.personas {
            let items = PersonaCorpus.items.filter { $0.persona == persona.id }
            #expect(items.count == 3, "\(persona.id)")
            #expect(items.allSatisfy { $0.terms.allSatisfy(persona.terms.contains) }, "\(persona.id)")
            #expect(items.allSatisfy { item in item.terms.allSatisfy { item.sentence.contains($0) } })
        }
    }

    @Test("terms are counted in any case, and errors against the sentence")
    func row() {
        let row = Self.row(.on, "Ask marlowen about Quorvex")
        #expect(row.termsHeard == 2)
        #expect(row.wordErrors.errors == 0)
        #expect(Self.row(.off, "ask Marlon about Corvex").termsHeard == 0)
    }

    @Test("the report shows the gain from the right words and the harm from the wrong ones")
    func gainAndHarm() {
        let report = PersonaReport(
            rows: [
                Self.row(.off, "ask Marlon about Corvex"), Self.row(.on, "ask Marlowen about Quorvex"),
                Self.row(.wrong, "ask Marlon about Corvex"),
            ])
        #expect(report.gain(of: "developer")! > 0.3)
        #expect(report.harm(to: "developer") == 0)
        #expect(report.harmed.isEmpty)
        #expect(report.markdown.contains("| developer | on | 1 | 2/2 | 0.0% |"))
        #expect(report.markdown.contains("Harm within the limit"))
    }

    @Test("harm over the limit fails the report and names the persona")
    func harmFails() {
        let report = PersonaReport(
            rows: [
                Self.row(.off, "ask Marlowen about Quorvex"), Self.row(.wrong, "ask Zenhollow about Quorvex"),
            ])
        #expect(report.harm(to: "developer")! > PersonaReport.harmLimit)
        #expect(report.harmed == ["developer"])
        #expect(report.markdown.contains("FAIL: harm over"))
    }
}
