import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken file name whose stem is a small word")
struct SpokenFileNameStemTests {
    private func cleaned(_ text: String) -> String {
        CleaningPipeline.standard.run(Draft(text: text)).text
    }

    @Test(
        "is written whole",
        arguments: [
            ("save it as out dot txt", "Save it as out.txt."),
            ("my out dot txt file", "My out.txt file."),
            ("save it as in dot sql", "Save it as in.sql."),
            ("my up dot txt file", "My up.txt file."),
            ("open about dot md", "Open about.md."),
        ])
    func writtenWhole(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "stays words after a determiner, which opens a phrase",
        arguments: [
            ("the dot md files", "The dot md files."),
            ("send it to the dot md", "Send it to the dot md."),
        ])
    func determinerStemStaysWords(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test("keeps a dot-file name apart from a function word")
    func dotFileNameStaysApart() {
        #expect(cleaned("edit the dot env file") == "Edit the .env file.")
    }
}
