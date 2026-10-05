// Tests for the abbreviation table: which written stops end a sentence, and which belong to the word.

import Testing

@testable import UttrflowCore

@Suite("One abbreviation table decides whether a written stop ends the sentence")
struct AbbreviationsTests {
    @Test("the bundled table loads, not the empty fallback")
    func tableLoads() {
        #expect(Abbreviations.table.source == .bundled)
        #expect(Abbreviations.table.rows.count >= 60)
    }

    @Test(
        "a stop before the next word ends the sentence by the abbreviation's kind and that word's case",
        arguments: [
            ("Dr.", "Rao", false), ("Mr.", "Shah", false), ("Mrs.", "Iyer", false),
            ("Ms.", "Jain", false),
            ("Prof.", "Kumar", false), ("St.", "Louis", false), ("Rev.", "Paul", false),
            ("Capt.", "Rao", false),
            ("dr.", "rao", false), ("e.g.", "Paris", false), ("i.e.", "Monday", false),
            ("vs.", "Delhi", false),
            ("cf.", "Section", false), ("viz.", "Three", false), ("etc.", "Then", true),
            ("etc.", "and", false),
            ("p.m.", "Sharp", true), ("p.m.", "sharp", false), ("a.m.", "We", true),
            ("a.m.", "tomorrow", false),
            ("Jan.", "5", false), ("Jan.", "The", true), ("Sept.", "twelfth", false),
            ("Dec.", "We", true),
            ("ft.", "long", false), ("ft.", "Then", true), ("lbs.", "of", false),
            ("oz.", "Add", true),
            ("Inc.", "The", true), ("Inc.", "announced", false), ("Ltd.", "and", false),
            ("Co.", "5", false),
            ("Corp.", "has", false), ("Jr.", "He", true), ("Jr.", "and", false),
            ("No.", "5", false),
            ("No.", "Then", true), ("no.", "then", true), ("fig.", "3", false),
            ("Dept.", "of", false),
            ("approx.", "ten", false), ("vol.", "2", false), ("U.S.", "The", true),
            ("U.S.", "and", false),
            ("U.K.", "office", false), ("Ph.D.", "She", true), ("Ph.D.", "in", false),
            ("J.", "Smith", true),
            ("J.", "and", false), ("A.", "Then", true), ("done.", "then", true),
            ("done.", "Then", true),
            ("home!", "we", true), ("why?", "we", true), ("Dr.", "\u{201C}Rao", false),
            ("example.com.", "then", true), ("3.5.", "then", true), ("ok,", "then", false),
            ("Inc.)", "The", true), ("Mt.", "Then", true),
        ])
    func endsSentenceBeforeAWord(word: String, next: String, ends: Bool) {
        #expect(Abbreviations.endsSentence(word, followedBy: next) == ends)
    }

    @Test(
        "at the end of the text a stop only an abbreviation owns keeps the sentence open",
        arguments: [
            ("p.m.", false), ("U.S.", false), ("e.g.", false), ("Dr.", false), ("vs.", false),
            ("etc.", false), ("Inc.", false), ("no.", true), ("A.", true), ("done.", true),
        ])
    func endsSentenceAtTheEnd(word: String, ends: Bool) {
        #expect(Abbreviations.endsSentence(word, followedBy: nil) == ends)
    }

    @Test(
        "a stop belongs to the word only where no everyday word shares the spelling",
        arguments: [
            ("etc", true), ("Dr", true), ("p.m", true), ("U.S", true), ("Inc", true), ("no", false),
            ("co", false), ("min", false), ("done", false), ("A", false), ("example.com", false),
        ])
    func ownsStop(word: String, owns: Bool) {
        #expect(Abbreviations.ownsStop(word) == owns)
    }

    @Test("kinds come from the table, and dotted letters and single letters from their shape")
    func kinds() {
        #expect(Abbreviations.kind(of: "Dr") == .title)
        #expect(Abbreviations.kind(of: "e.g") == .leadIn)
        #expect(Abbreviations.kind(of: "Jan") == .month)
        #expect(Abbreviations.kind(of: "N.Y") == .acronym)
        #expect(Abbreviations.kind(of: "J") == .initial)
        #expect(Abbreviations.kind(of: "done") == nil)
    }
}
