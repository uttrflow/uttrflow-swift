import Testing
import UttrflowCore

@testable import UttrflowAI

/// Holds every sentence-local pass to reading no further back than the sentence it is cleaning. See `PLAN.md`.
@Suite("Sentence locality")
struct SentenceLocalityTests {
    /// A complete sentence whose last word is bait for some rule's lookback.
    static let prefixes = [
        "the glass was full.", "I bought something new.", "hand me a pen.",
        "we are in the room.", "the meeting is at 3.", "I have a hundred.",
        "put it there.", "give me the number.", "is the build red?", "what a mess!",
        "she is full.", "we shipped it.",
    ]

    /// A sentence a rule acts on, or declines to act on, for reasons that lie inside it.
    static let bodies = [
        "no 4 people confirmed", "Stop worrying about it", "Line up here",
        "Six people came", "Comma then go", "And fifty people came",
        "point two is ready", "one of them works", "period costumes are fun",
        "dash over to the shop", "I said no to the offer", "we need to wait to finish",
        "number one is broken", "full stop the engine", "two no three cats", "Stop.",
    ]

    static let passes: [(name: String, pass: any CleaningPass)] = [
        ("FillersPass", FillersPass()), ("StammersPass", StammersPass()),
        ("RepeatedPhrasePass", RepeatedPhrasePass()), ("SelfCorrectionPass", SelfCorrectionPass()),
        ("SpokenPunctuationPass", SpokenPunctuationPass()), ("LayoutWordsPass", LayoutWordsPass()),
        ("NumberFormsPass", NumberFormsPass()),
        ("NumberFormsPass(.always)", NumberFormsPass(policy: .always)),
        ("ContractionsPass", ContractionsPass()), ("SpacingPass", SpacingPass()),
    ]

    /// The pass and sentence of issue #254, where "is this phrase first" is asked of the text; it may shrink, never grow.
    static let readsTheTextNotTheSentence = [("LayoutWordsPass", "number one is broken")]

    /// A mark said by name is written onto the word before it even across a stop, the recogniser's boundary being a guess and the spoken mark an instruction.
    static func attachesBackwards(_ body: String) -> Bool {
        let opening = body.split(separator: " ").map { WordShape(String($0)).key }
        return SpokenPunctuationPass.marks.contains { opening.starts(with: $0.words) }
    }

    @Test("a preceding sentence changes nothing about how the sentence after it is cleaned")
    func aPrecedingSentenceChangesNothing() {
        for (name, pass) in Self.passes {
            for body in Self.bodies where !Self.attachesBackwards(body) {
                guard !Self.readsTheTextNotTheSentence.contains(where: { $0 == (name, body) })
                else { continue }
                let alone = cleaned(body, by: pass)
                for prefix in Self.prefixes {
                    #expect(
                        cleaned("\(prefix) \(body)", by: pass) == "\(prefix) \(alone)",
                        "\(name): '\(prefix) \(body)'")
                }
            }
        }
    }

    /// The exemption is a property of the sentence, not a licence for the pass, so it must stay this narrow.
    @Test("only a sentence opening on a spoken mark is exempt")
    func theExemptionIsNarrow() {
        #expect(Self.attachesBackwards("Comma then go"))
        #expect(Self.attachesBackwards("full stop the engine"))
        #expect(Self.attachesBackwards("period costumes are fun"))
        #expect(!Self.attachesBackwards("Line up here"))
        #expect(!Self.attachesBackwards("number one is broken"))
        #expect(
            Self.bodies.filter(Self.attachesBackwards) == [
                "Comma then go", "period costumes are fun", "dash over to the shop",
                "full stop the engine",
            ])
    }

    /// A known defect stays known: it must still fail, or its entry is stale and goes.
    @Test("the case issue #254 owns still reads the text rather than the sentence")
    func theKnownCaseStillFails() {
        #expect(Self.readsTheTextNotTheSentence.count == 1)
        let pass = LayoutWordsPass()
        #expect(cleaned("number one is broken", by: pass) == "number one is broken")
        #expect(
            cleaned("the build failed. number one is broken", by: pass)
                != "the build failed. number one is broken")
    }
}
