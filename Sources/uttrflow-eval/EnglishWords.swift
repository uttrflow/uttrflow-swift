// The `english-words` command: the English-word test, for scorers outside this package.
import ArgumentParser
private import UttrflowCore

/// Reads one word per line and prints 1 when `LexicalClass.isKnownEnglishWord` holds and 0 when not. See Docs/ordinary-words.md.
struct EnglishWords: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "english-words",
        abstract: "Print 1 for each input word the English model knows and 0 for each it does not."
    )

    func run() throws {
        while let line = readLine(strippingNewline: true) {
            print(LexicalClass.isKnownEnglishWord(line) ? 1 : 0)
        }
    }
}
