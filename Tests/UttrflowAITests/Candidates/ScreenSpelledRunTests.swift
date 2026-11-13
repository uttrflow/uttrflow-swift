import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A surely heard run that spells an identifier on screen is offered that identifier")
struct ScreenSpelledRunTests {
    private func draft(_ text: String, at score: Double = 0.95) -> Draft {
        Draft(words: text.split(separator: " ").map { Draft.Word(String($0), evidence: .score(score)) })
    }

    private let sentence = "the crash only happens in payment sheet after the card scanner closes"

    @Test("words heard surely that close up to an identifier on screen are offered it")
    func spelledRunIsOffered() async {
        let spans = await DoubtfulWords.standard.spans(
            in: draft(sentence), for: .showing(title: "PaymentSheet.swift PaymentSheet"))
        let run = spans.first { $0.heard == "payment sheet" }
        #expect(run?.reason == .spelledOnScreen)
        #expect(run?.candidates.map(\.spelling).contains("PaymentSheet") == true)
    }

    @Test("a screen that does not show the identifier offers nothing for the same sentence")
    func absentIdentifierIsNotOffered() async {
        let spans = await DoubtfulWords.standard.spans(
            in: draft(sentence), for: .showing(title: "Checkout board"))
        #expect(!spans.contains { $0.heard == "payment sheet" })
    }

    @Test("a single word that the screen also shows is not doubted")
    func singleWordIsNotDoubted() async {
        let spans = await DoubtfulWords.standard.spans(
            in: draft("open the sheet now"), for: .showing(title: "sheet"))
        #expect(!spans.contains { $0.reason == .spelledOnScreen })
    }

    @Test("the prompt line says the screen spells the run")
    func promptLineSaysWhy() {
        let span = DoubtfulSpan(
            heard: "payment sheet", confidence: 0.92, reason: .spelledOnScreen, candidates: ["PaymentSheet"])
        #expect(
            PromptBuilder.doubtfulText([span])
                == "\"payment sheet\" (heard at 0.92, spelled so on screen) — could be: PaymentSheet")
    }
}
