import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import Uttrflow

@Suite("Personal data export disclosure")
struct PersonalDataExportTests {
    @Test("warns that exported JSON is not encrypted and offers secret-snippet exclusion")
    func disclosesPlaintextAndExclusionChoice() {
        #expect(PersonalDataExport.disclosureMessage.contains("not encrypted"))
        #expect(PersonalDataExport.disclosureMessage.contains("exclude snippets"))
    }

    @Test("excludes snippets containing recognized credentials when chosen")
    func excludesRecognizedCredentialSnippets() {
        let archive = PersonalDataExport.archive(
            dictionary: [],
            snippets: [
                .init(trigger: "safe phrase", expansion: "ordinary text", created: .distantPast),
                .init(trigger: "database login", expansion: "password=hunter2", created: .distantPast),
            ],
            choice: .excludeSecretSnippets)

        #expect(archive.snippets.map(\.trigger) == ["safe phrase"])
    }

    @Test("keeps every snippet when the user chooses to include them")
    func includesAllSnippetsWhenChosen() {
        let snippets: [Snippet] = [
            .init(trigger: "database login", expansion: "password=hunter2", created: .distantPast)
        ]

        let archive = PersonalDataExport.archive(
            dictionary: [], snippets: snippets, choice: .includeAllSnippets)

        #expect(archive.snippets == snippets)
    }

    /// Every key the export may write, per level; anything learned beyond these, such as the evidence ledger, fails.
    @Test("the written export holds only the allow-listed fields")
    func writesOnlyAllowListedFields() throws {
        let entry = DictionaryEntry(
            word: "Orvanta", pronunciations: ["or vanta", "or wanta"], origin: .learned,
            firstSeen: .distantPast, timesUsed: 3, timesReverted: 1)
        let snippet = Snippet(
            trigger: "my sign off", expansion: "Thanks again", created: .distantPast, timesUsed: 2,
            lastUsed: .distantPast)
        let data = try PersonalDataExport.archive(
            dictionary: [entry], snippets: [snippet], choice: .includeAllSnippets
        ).encoded()

        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(top["dictionary"] as? [[String: Any]])
        let snippets = try #require(top["snippets"] as? [[String: Any]])
        #expect(Set(top.keys) == ["version", "dictionary", "snippets"])
        #expect(
            Set(entries.flatMap(\.keys)) == [
                "id", "word", "pronunciation", "pronunciations", "origin", "firstSeen", "timesUsed",
                "timesReverted",
            ])
        #expect(
            Set(snippets.flatMap(\.keys)) == [
                "id", "trigger", "expansion", "created", "timesUsed", "lastUsed",
            ])
    }
}
