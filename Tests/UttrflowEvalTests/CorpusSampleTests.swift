import Foundation
import Testing

@testable import UttrflowEval

@Suite("A sample from the catalogue")
struct CorpusSampleTests {
    /// BCP-47 has no tag for Hinglish, so the stress decides, or the language breakdown measures nothing.
    @Test("code-switching means Hinglish whatever the tag says")
    func spokenLanguage() {
        #expect(makeSample("a", language: "en-GB").spokenLanguage == .english)
        #expect(makeSample("b", language: "hi-IN").spokenLanguage == .hindi)
        #expect(makeSample("c", language: "hi-IN", stresses: ["code-switching"]).spokenLanguage == .hinglish)
        #expect(makeSample("d", language: "en-IN", stresses: ["code-switching"]).spokenLanguage == .hinglish)
    }

    @Test("a Devanagari reference is filed under Devanagari, not romanised into existence")
    func scripts() {
        let hindi = makeSample("hi", language: "hi-IN", reference: "वो query बहुत slow चल रही है")
        #expect(hindi.passage.devanagari == "वो query बहुत slow चल रही है")
        // No Latin form exists, and pretending one does would score a Latin transcript against nothing.
        #expect(hindi.passage.reference(in: .latin) == nil)
        #expect(hindi.passage.forms.count == 1)

        let english = makeSample("en")
        #expect(english.passage.reference(in: .latin) == "the build passed ship it")
        #expect(english.passage.devanagari == nil)
    }

    /// An accented or noisy sample is not an easy one, so it must not be filed under the floor category.
    @Test("an unmapped stress becomes 'other' rather than 'everyday'")
    func stressMapping() {
        #expect(makeSample("a", stresses: ["proper-nouns"]).passage.stressor == .properNouns)
        #expect(makeSample("b", stresses: ["numbers-and-units"]).passage.stressor == .digits)
        #expect(makeSample("c", stresses: ["technical-dictation"]).passage.stressor == .technical)
        #expect(makeSample("d", stresses: ["domain-jargon"]).passage.stressor == .technical)
        #expect(makeSample("e", stresses: ["disfluency"]).passage.stressor == .falseStarts)
        #expect(makeSample("f", stresses: ["punctuation"]).passage.stressor == .everyday)
        #expect(makeSample("g", stresses: ["accent"]).passage.stressor == .other)
        #expect(makeSample("h", stresses: ["background-noise", "quiet-speech"]).passage.stressor == .other)
        // The full list survives whatever the typed axis does with it.
        #expect(
            makeSample("i", stresses: ["accent", "punctuation"]).passage.stresses == [
                "accent", "punctuation",
            ])
    }

    @Test("a passage keeps the sample's duration")
    func duration() {
        #expect(makeSample("a").duration == .milliseconds(4_000))
    }

    /// A hand-written passage says what it stresses once; a second list is how the two come to disagree.
    @Test("a hand-written passage derives its stress list from its stressor")
    func handWrittenStresses() {
        let passage = TranscriptionCase(
            id: "one", language: .english, stressor: .properNouns, romanised: "Priya Raghunathan")
        #expect(passage.stresses == ["properNouns"])
    }

    /// The recordings outlive several versions of this type; a new field must not mean a re-record.
    @Test("a passage recorded before the stress list existed still decodes")
    func decodesAnOlderPassage() throws {
        let older = """
            {"id":"en-standup","language":"english","stressor":"everyday",
             "romanised":"ship it","mustKeep":["ship"]}
            """
        let passage = try JSONDecoder().decode(TranscriptionCase.self, from: Data(older.utf8))
        #expect(passage.stresses == ["everyday"])
        #expect(passage.mustKeep == ["ship"])
        #expect(passage.devanagari == nil)
    }

    @Test("a page knows how much more there is")
    func page() {
        let page = CorpusPage(total: 1_000, count: 2, samples: [makeSample("a"), makeSample("b")])
        #expect(page.total == 1_000)
        #expect(page.samples.count == page.count)
        #expect(CorpusQuery.maximumPageSize == 500)
    }
}

@Suite("Naming a sample the catalogue will accept")
struct CorpusSlugTests {
    /// Checked before a word is spoken, since a slug rejected at upload time comes after forty passages.
    @Test("matches the backend's url_slug domain")
    func validity() {
        #expect(CorpusSlug.isValid("en-standup"))
        #expect(CorpusSlug.isValid("a1"))
        #expect(CorpusSlug.isValid(String(repeating: "a", count: 64)))
        #expect(!CorpusSlug.isValid("a"), "one character is below the domain's floor")
        #expect(!CorpusSlug.isValid(String(repeating: "a", count: 65)))
        #expect(!CorpusSlug.isValid("-leading"))
        #expect(!CorpusSlug.isValid("Upper-Case"))
        #expect(!CorpusSlug.isValid("has space"))
        #expect(!CorpusSlug.isValid("under_score"))
        #expect(!CorpusSlug.isValid(""))
    }

    @Test("puts the cohort first, so a bucket sorts by sitting")
    func naming() {
        #expect(CorpusSlug.make(passage: "en-standup", cohort: "naveen-quiet") == "naveen-quiet-en-standup")
        // No `unattributed-` prefix: it would become part of the key, and nobody renames a thousand objects.
        #expect(CorpusSlug.make(passage: "en-standup", cohort: nil) == "en-standup")
    }

    @Test("folds what a person types into what Postgres will take")
    func sanitising() {
        #expect(CorpusSlug.sanitised("Naveen's Quiet Room") == "naveen-s-quiet-room")
        #expect(CorpusSlug.sanitised("  spaced  out  ") == "spaced-out")
        #expect(CorpusSlug.sanitised("!!!") == "")
        #expect(CorpusSlug.sanitised("café") == "caf")
        // Not truncated: two long names agreeing in their first sixty-four characters would become one slug.
        #expect(CorpusSlug.sanitised(String(repeating: "a", count: 100)).count == 100)
        #expect(!CorpusSlug.isValid(CorpusSlug.sanitised(String(repeating: "a", count: 100))))
    }

    @Test("a cohort carries who and where, and names the recordings that have neither")
    func cohorts() {
        let cohort = RecordingCohort(id: "naveen-quiet", speaker: "naveen", setting: "quiet room")
        #expect(cohort.description == "naveen · quiet room")
        #expect(RecordingCohort.unattributed == "unattributed")
    }
}
