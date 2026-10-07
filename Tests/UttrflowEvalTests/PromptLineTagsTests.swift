import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// Every bullet line of the shipped prompt carries one tag, and no new line asks the model for a class the rules own.
@Suite("Prompt line tags")
struct PromptLineTagsTests {
    /// Each scope's bullet lines: the contract under `nil`, then each shipped block.
    static let scopes: [(PromptBlockID?, [String])] =
        [(nil, PromptLineTags.bullets(in: PromptContract.text))]
        + PromptBlocks.standard.values.map { ($0.id, PromptLineTags.bullets(in: $0.rules)) }

    /// The lines that still ask the model for a rules-owned class; removing one needs a `make bakeoff` run, and this set never grows.
    static let rulesOwnedLines: Set<String> = [
        "- remove fillers", "- when a speaker explicitly corrects",
        "document - full sentences; keep the breaks", "spreadsheet - numbers as numerals",
        "sqlEditor - numerals for numbers", "codeEditor - keep every line break",
        "terminal - keep every line break", "messaging - keep the greeting", "plain - keep every line break",
    ]

    static func key(_ tag: PromptLineTag) -> String {
        tag.block.map { "\($0) \(tag.opening)" } ?? tag.opening
    }

    @Test("tags every bullet line of the contract and each block exactly once")
    func everyLineHasOneTag() {
        for (block, lines) in Self.scopes {
            let tags = PromptLineTags.all.filter { $0.block == block }
            for line in lines {
                let matches = tags.filter { line.hasPrefix($0.opening) }
                #expect(matches.count == 1, "\(block?.rawValue ?? "contract"): \(line)")
            }
        }
    }

    @Test("has no tag for a line the prompt no longer has")
    func noStaleTag() {
        for tag in PromptLineTags.all {
            let lines = Self.scopes.first { $0.0 == tag.block }?.1 ?? []
            #expect(lines.contains { $0.hasPrefix(tag.opening) }, "\(Self.key(tag))")
        }
    }

    @Test("asks the model for a rules-owned class only on the recorded lines")
    func rulesOwnedLinesNeverGrow() {
        let found = Set(PromptLineTags.all.filter { !$0.rulesOwnedClasses.isEmpty }.map(Self.key))
        #expect(found == Self.rulesOwnedLines)
    }

    @Test("names a formatting class on every line that formats")
    func formattingLinesNameAClass() {
        for tag in PromptLineTags.all {
            if case .formats(let classes) = tag.ask {
                #expect(!classes.isEmpty, "\(Self.key(tag))")
            }
        }
    }

    @Test("fails a line with no tag")
    func untaggedLineIsCaught() {
        #expect(!PromptLineTags.all.contains { "- an invented rule".hasPrefix($0.opening) })
    }
}
