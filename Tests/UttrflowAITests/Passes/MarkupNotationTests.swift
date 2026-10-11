import Testing
import UttrflowCore
import UttrflowEval

@testable import UttrflowAI

/// Spoken tags, attributes, selectors and declarations are written as HTML and CSS, and prose around them is not.
@Suite("Markup notation in a code editor")
struct MarkupNotationTests {
    /// The corpus's cases, each with the one text it must be written as.
    static let notation = EvaluationCorpus.all.filter {
        $0.id.hasPrefix("markup-html-") || $0.id.hasPrefix("markup-css-")
    }
    static let prose = EvaluationCorpus.markupProse

    /// The words the passes before the model write for `spoken` at a caret in `documentName` after `before`.
    private static func written(_ spoken: String, in documentName: String, after before: String) -> String {
        let app = AppContext(documentName: documentName, precedingText: before)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        return CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
            .run(Draft(text: spoken)).text
    }

    private static func written(_ testCase: EvaluationCase) -> String {
        written(
            testCase.spoken, in: testCase.context.documentName ?? "",
            after: testCase.context.precedingText ?? "")
    }

    @Test("holds twenty HTML cases, twenty CSS cases and the prose that must stay")
    func counts() {
        #expect(Self.notation.count { $0.id.hasPrefix("markup-html-") } == 20)
        #expect(Self.notation.count { $0.id.hasPrefix("markup-css-") } == 20)
        #expect(Self.prose.count == 12)
    }

    @Test("writes every case exactly")
    func writesExactly() {
        for testCase in Self.notation {
            #expect(Self.written(testCase) == testCase.expectedExact, "\(testCase.id)")
        }
    }

    @Test("adds no word and no mark that was not named")
    func convertsNotationOnly() {
        let table = NotationAlignment.notationRows + SpokenCommands.markup
        for testCase in Self.notation {
            let written = Self.written(testCase)
            let alignment = NotationAlignment.align(spoken: testCase.spoken, written: written, table: table)
            #expect(alignment.unsourced.isEmpty, "\(testCase.id) invents \(alignment.unsourced)")
            #expect(alignment.dropped.isEmpty, "\(testCase.id) drops \(alignment.dropped)")
        }
    }

    @Test("leaves prose in HTML text, a comment or a quoted value as spoken")
    func abstainsOnProse() async throws {
        #expect(!Self.prose.isEmpty)
        for testCase in Self.prose {
            let output = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
            let words = Set(output.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            for word in testCase.mustKeep {
                #expect(words.contains(word), "\(testCase.id) loses \(word)")
            }
            for mark in testCase.mustNotAdd where !testCase.spoken.contains(mark) {
                #expect(!output.contains(mark), "\(testCase.id) adds \(mark)")
            }
            let alignment = NotationAlignment.align(spoken: testCase.spoken, written: output)
            #expect(alignment.unsourced.isEmpty, "\(testCase.id) invents \(alignment.unsourced)")
        }
    }

    @Test("closes nothing the speaker did not close")
    func closesNothing() {
        let body = "<body>\n"
        #expect(
            Self.written("open div class equals hero", in: "index.html", after: body)
                == "open div class equals hero")
        #expect(
            Self.written("open div class equals hero and", in: "index.html", after: body)
                == "open div class equals hero and")
        #expect(Self.written("open div", in: "index.html", after: body) == "open div")
    }

    @Test("writes a tag in the middle of text without touching the words around it")
    func tagInsideText() {
        #expect(
            Self.written("open span close hello open slash span close", in: "index.html", after: "<p>")
                == "<span> hello </span>")
        #expect(
            Self.written("open p close the door", in: "index.html", after: "<body>\n")
                == "open p close the door")
    }

    @Test("reads a word as markup only in the slot its row names")
    func slotsOfRows() {
        #expect(Self.written("close", in: "index.html", after: "<body>\n") == "close")
        #expect(Self.written("close", in: "index.html", after: "<div class=hero ") == ">")
        #expect(Self.written("dot hero", in: "site.css", after: ".a {\n  ") != ".hero")
        #expect(Self.written("dot hero", in: "site.css", after: "") == ".hero")
        #expect(Self.written("hero colon hover", in: "site.css", after: "") == "hero:hover")
        #expect(Self.written("hero colon hover", in: "site.css", after: ".a {\n  ") == "hero: hover")
    }

    @Test("spells a tag only from an element, its attributes and a close")
    func spellsTag() {
        func spells(_ text: String) -> Bool {
            NotationEvidence.spellsTag(in: text.split(separator: " ").map(String.init))
        }
        #expect(spells("open div close"))
        #expect(spells("open slash div close"))
        #expect(spells("open a href equals open quote about close quote close"))
        #expect(spells("open br slash close"))
        #expect(!spells("open the door and close it"))
        #expect(!spells("open table close to the window"))
        #expect(!spells("open div class equals"))
        #expect(!spells("open div and close"))
        #expect(!spells("open div equals equals close"))
        #expect(!spells("open slash div class equals hero close"))
        #expect(!spells("open widget close"))
    }

    @Test("rules out markup in a comment or a quoted value and says nothing about text")
    func evidence() {
        #expect(NotationEvidence.applicability(markup: .quoted) == .ruledOut(by: .caretInProse))
        #expect(NotationEvidence.applicability(markup: .slot(.text)) == .noEvidence)
        #expect(
            NotationEvidence.applicability(markup: .slot(.tag))
                == .evidenced(confidence: 1, by: [.caretInCode]))
        #expect(NotationEvidence.mayActivate(.noEvidence, in: .codeEditor, markup: .slot(.text)))
        #expect(!NotationEvidence.mayActivate(.noEvidence, in: .codeEditor))
        #expect(!NotationEvidence.mayActivate(.ruledOut(by: .caretInProse), in: .codeEditor, markup: .quoted))
    }

    @Test("keeps a markup row out of the commands a snippet trigger collides with")
    func snippetTriggers() {
        #expect(SpokenCommands.phrase(within: ["open"]) == nil)
        #expect(SpokenCommands.markup.count >= 16)
        #expect(SpokenCommands.markup.allSatisfy { $0.slots != nil })
    }
}
