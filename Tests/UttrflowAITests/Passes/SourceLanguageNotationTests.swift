import Testing
import UttrflowCore

@testable import UttrflowAI

/// A symbol said in words is written for the language of the file, and left as words in a language that has none.
@Suite("Source notation per language", .bug(id: 4223))
struct SourceLanguageNotationTests {
    private func written(_ spoken: String, in file: String) -> String {
        let app = AppContext(
            applicationName: "Code", bundleIdentifier: "com.microsoft.VSCode", documentName: file,
            precedingText: "", accessibilityRole: "AXTextArea", isMultiline: true)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
        return pipeline.run(Draft(text: spoken)).text
    }

    @Test(
        "writes the path and logical operators the language has",
        arguments: [
            ("ready logical and done", "main.go", "ready && done"),
            ("ready logical or done", "Main.java", "ready || done"),
            ("ready pipe pipe done", "lib.rs", "ready || done"),
            ("ready double pipe done", "app.ts", "ready || done"),
            ("count colon equals one", "main.go", "count := 1"),
        ])
    func writesNotation(spoken: String, file: String, expected: String) {
        #expect(written(spoken, in: file) == expected)
    }

    @Test(
        "leaves the words alone in a language with no such symbol",
        arguments: [
            ("tom double pipe jerry", "notes.py"),
            ("tom double colon jerry", "notes.go"),
        ])
    func leavesWords(spoken: String, file: String) {
        #expect(!written(spoken, in: file).contains("||") && !written(spoken, in: file).contains("::"))
    }
}
