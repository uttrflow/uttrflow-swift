import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite(
    "Vocabulary prompt under a language hint: what each condition hands the recogniser and how a clip is scored"
)
struct VocabularyPromptProbeTests {
    private static let item = VocabularyPromptItem(
        id: "t", sentence: "कल वरीकेश से मिलना है", names: ["वरीकेश"], romanisedNames: ["Varikesh"])

    @Test("each condition hands over the names in its own script and place")
    func prompts() {
        #expect(VocabularyPromptCondition.none.prompt(for: Self.item) == ([], nil))
        #expect(VocabularyPromptCondition.latinFrame.prompt(for: Self.item) == (["Varikesh"], nil))
        #expect(VocabularyPromptCondition.devanagariFrame.prompt(for: Self.item) == (["वरीकेश"], nil))
        #expect(VocabularyPromptCondition.wordsOnly.prompt(for: Self.item) == ([], "वरीकेश"))
    }

    @Test("a transcript in Devanagari that holds the name stays in Devanagari and hears it")
    func devanagariTranscript() {
        let row = VocabularyPromptRow(
            item: Self.item, hint: "hi", condition: .none, transcript: "कल वरीकेश से मिलना है।")
        #expect(row.devanagariShare == 1)
        #expect(!row.leftDevanagari)
        #expect(row.namesHeard == 1)
        #expect(row.wordErrors.errors == 0)
    }

    @Test("an English transcript leaves Devanagari, and the name counts in its Latin spelling")
    func englishTranscript() {
        let row = VocabularyPromptRow(
            item: Self.item, hint: "auto", condition: .latinFrame,
            transcript: "I have to meet Varikesh tomorrow.")
        #expect(row.devanagariShare == 0)
        #expect(row.leftDevanagari)
        #expect(row.namesHeard == 1)
        #expect(row.wordErrors.errors > 0)
    }

    @Test("an empty transcript leaves Devanagari and hears nothing")
    func emptyTranscript() {
        let row = VocabularyPromptRow(item: Self.item, hint: "hi", condition: .wordsOnly, transcript: "")
        #expect(row.leftDevanagari)
        #expect(row.namesHeard == 0)
    }

    @Test("the table sums each hint and condition apart from the others")
    func table() {
        func row(
            _ hint: String, _ condition: VocabularyPromptCondition, _ transcript: String
        ) -> VocabularyPromptRow {
            VocabularyPromptRow(item: Self.item, hint: hint, condition: condition, transcript: transcript)
        }
        let rows = [
            row("hi", .none, "कल वरीकेश से मिलना है"), row("hi", .none, "kal milna hai"),
            row("hi", .wordsOnly, "कल वरीकेश से मिलना है"), row("auto", .none, "I have to meet Varikesh"),
        ]
        let lines = VocabularyPromptTable(rows: rows).markdown.split(separator: "\n").dropFirst(2)
        #expect(
            lines == [
                "| auto | none | 1 | 1 | 0.0% | 1/1 | 100.0% |",
                "| hi | none | 2 | 1 | 50.0% | 1/2 | 50.0% |",
                "| hi | wordsOnly | 1 | 0 | 100.0% | 1/1 | 0.0% |",
            ])
    }

    @Test("a tab or line break in a transcript stays inside its one record")
    func tabSeparated() {
        let row = VocabularyPromptRow(
            item: Self.item, hint: "hi", condition: .none, transcript: "one\ttwo\nthree\r")
        #expect(row.tabSeparated == "t\thi\tnone\tone\\ttwo\\nthree\\r")
    }

    @Test("a literal backslash is written doubled, so it cannot be read as an escape")
    func backslash() {
        let row = VocabularyPromptRow(
            item: Self.item, hint: "hi", condition: .none, transcript: "a\\nb\nc")
        #expect(row.tabSeparated == "t\thi\tnone\ta\\\\nb\\nc")
    }

    @Test("every corpus item names what its sentence says, in both scripts")
    func corpus() {
        #expect(!VocabularyPromptCorpus.items.isEmpty)
        #expect(Set(VocabularyPromptCorpus.items.map(\.id)).count == VocabularyPromptCorpus.items.count)
        for item in VocabularyPromptCorpus.items {
            #expect(item.names.count == item.romanisedNames.count, "\(item.id)")
            #expect(item.names.allSatisfy { item.sentence.contains($0) }, "\(item.id)")
        }
    }
}
