// The `normalise` command: the one word-normalisation rule, for scorers outside this package.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Reads one text per line and prints the words `TextNormaliser.standard` compares, so every scorer counts the same words.
struct NormaliseText: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "normalise",
        abstract: "Print the words each input line is scored over, one output line per input line."
    )

    @Flag(name: .long, help: "Print the normalisation rules in force, one line, and exit.")
    var rules = false

    func run() throws {
        if rules {
            print(TextNormaliser.standard.rules.map(\.rawValue).joined(separator: ","))
            return
        }
        while let line = readLine(strippingNewline: true) {
            print(TextNormaliser.standard.normalised(line))
        }
    }
}
