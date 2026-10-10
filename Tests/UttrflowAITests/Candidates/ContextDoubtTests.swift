import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A surely heard word that sits apart from its sentence is doubted")
struct ContextDoubtTests {
    /// Every word at `score`, so only the sentence decides which one is doubted.
    private func words(
        _ text: String, at score: Double
    ) -> [(text: String, confidence: Double, settled: Bool)] {
        text.split(separator: " ").map { (String($0), score, false) }
    }

    private func draft(_ text: String, at score: Double) -> Draft {
        Draft(words: words(text, at: score).map { Draft.Word($0.text, evidence: .score($0.confidence)) })
    }

    private let ticket = "we need to meet the slaw for this ticket by the deadline"

    @Test("a known word far from every other word is doubted, and its neighbours are not")
    func farWordIsDoubted() {
        let found = ContextDoubt.doubted(words(ticket, at: 0.8))
        #expect(found == [5])
    }

    @Test("a word the embedding does not hold is doubted")
    func unknownWordIsDoubted() {
        let found = ContextDoubt.doubted(words("please file it in Yerub before lunch", at: 0.8))
        #expect(found == [4])
    }

    @Test("a score at the vouching line, or below the certainty threshold, is not context's to doubt")
    func scoreOutsideTheBandIsNotAsked() {
        #expect(ContextDoubt.doubted(words(ticket, at: ContextDoubt.vouchingScore)).isEmpty)
        #expect(ContextDoubt.doubted(words(ticket, at: 0.3)).isEmpty)
    }

    @Test("a romanised Hindi sentence is never doubted for being unknown to the English embedding")
    func hindiIsNotDoubted() {
        #expect(ContextDoubt.doubted(words("mujhe kal tak report bhejna hai", at: 0.8)).isEmpty)
    }

    @Test("a word apart from its sentence is offered its readings as out of context")
    func apartWordIsOffered() async {
        let source = TableSource(readings: ["slaw": ["SLA"]])
        let spans = await DoubtfulWords(sources: [source]).spans(in: draft(ticket, at: 0.8), for: .unknown)
        #expect(spans.map(\.heard) == ["slaw"])
        #expect(spans.first?.reason == .outOfContext)
        #expect(spans.first?.candidates == ["SLA"])
    }

    @Test("a word a source holds as heard is never doubted for its sentence")
    func vouchedWordIsKept() async {
        let source = TableSource(readings: ["slaw": ["SLA"]], held: ["slaw"])
        let spans = await DoubtfulWords(sources: [source]).spans(in: draft(ticket, at: 0.8), for: .unknown)
        #expect(spans.isEmpty)
    }

    @Test("the screen vouches for a word it shows")
    func screenVouches() async {
        let screen = ScreenCandidates()
        #expect(await screen.vouches(for: "Yerub", in: .showing(title: "Yerub board")))
        #expect(!(await screen.vouches(for: "Yerub", in: .showing(title: "Sprint board"))))
    }

    @Test("a shipped technical term vouches for itself")
    func technicalTermVouches() async {
        #expect(await TechnicalCandidates().vouches(for: "Kubernetes", in: .unknown))
        #expect(!(await TechnicalCandidates().vouches(for: "slaw", in: .unknown)))
    }

    @Test("the prompt line says why a surely heard word is doubted")
    func promptLineSaysWhy() {
        let span = DoubtfulSpan(heard: "slaw", confidence: 0.8, reason: .outOfContext, candidates: ["SLA"])
        #expect(
            PromptBuilder.doubtfulText([span])
                == "\"slaw\" (heard at 0.80, unusual in this sentence) — could be: SLA")
    }
}

/// A source answering and vouching from fixed tables, so the test measures the doubt and nothing else.
private struct TableSource: CandidateSource {
    let readings: [String: [String]]
    var held: Set<String> = []

    func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        (readings[word.text] ?? []).map { Reading($0) }
    }

    func vouches(for heard: String, in situation: Situation) async -> Bool { held.contains(heard) }
}
