import Testing
import UttrflowCore

@testable import UttrflowAI

/// Probe: runs a misheard homophone through the candidate sources and the guard at three recogniser scores.
@Suite("Homophone doubt and the confident-homophone guard, read together")
struct HomophonePolicyProbeTests {
    /// One sentence as heard with the wrong member, and as meant.
    struct Case: Sendable, CustomStringConvertible {
        let heard: String
        let meant: String
        let wrong: String
        let right: String
        var description: String { heard }
    }

    static let scores = [0.3, 0.6, 0.95]

    static let functionWordCases: [Case] = [
        Case(heard: "send it too me", meant: "send it to me", wrong: "too", right: "to"),
        Case(heard: "i want to come to", meant: "i want to come too", wrong: "to", right: "too"),
        Case(heard: "put it over their", meant: "put it over there", wrong: "their", right: "there"),
        Case(heard: "there car is red", meant: "their car is red", wrong: "there", right: "their"),
        Case(
            heard: "the dog wagged it's tail", meant: "the dog wagged its tail", wrong: "it's", right: "its"),
        Case(heard: "its raining today", meant: "it's raining today", wrong: "its", right: "it's"),
        Case(heard: "you're bag is here", meant: "your bag is here", wrong: "you're", right: "your"),
        Case(heard: "your late again", meant: "you're late again", wrong: "your", right: "you're"),
        Case(heard: "this is four you", meant: "this is for you", wrong: "four", right: "for"),
        Case(heard: "we need for chairs", meant: "we need four chairs", wrong: "for", right: "four"),
        Case(heard: "i will by milk", meant: "i will buy milk", wrong: "by", right: "buy"),
        Case(heard: "stand buy the door", meant: "stand by the door", wrong: "buy", right: "by"),
        Case(heard: "i can hear you hear", meant: "i can hear you here", wrong: "hear", right: "here"),
        Case(
            heard: "come over here and here this", meant: "come over here and hear this", wrong: "here",
            right: "hear"),
        Case(heard: "we one the match", meant: "we won the match", wrong: "one", right: "won"),
        Case(heard: "give me won apple", meant: "give me one apple", wrong: "won", right: "one"),
        Case(heard: "i no the answer", meant: "i know the answer", wrong: "no", right: "know"),
        Case(heard: "there is know milk", meant: "there is no milk", wrong: "know", right: "no"),
        Case(heard: "this is hour house", meant: "this is our house", wrong: "hour", right: "our"),
        Case(heard: "wait an our please", meant: "wait an hour please", wrong: "our", right: "hour"),
    ]

    static let senseCases: [Case] = [
        Case(heard: "we ship next weak", meant: "we ship next week", wrong: "weak", right: "week"),
        Case(heard: "the signal is week", meant: "the signal is weak", wrong: "week", right: "weak"),
        Case(heard: "a peace of the cake", meant: "a piece of the cake", wrong: "peace", right: "piece"),
        Case(
            heard: "they signed a piece treaty", meant: "they signed a peace treaty", wrong: "piece",
            right: "peace"),
        Case(heard: "lets meat at noon", meant: "lets meet at noon", wrong: "meat", right: "meet"),
        Case(heard: "the meet is cold", meant: "the meat is cold", wrong: "meet", right: "meat"),
        Case(heard: "press the break pedal", meant: "press the brake pedal", wrong: "break", right: "brake"),
        Case(heard: "take a short brake", meant: "take a short break", wrong: "brake", right: "break"),
        Case(heard: "the shoes are on sail", meant: "the shoes are on sale", wrong: "sail", right: "sale"),
        Case(heard: "we sale at dawn", meant: "we sail at dawn", wrong: "sale", right: "sail"),
        Case(heard: "i ate the hole pie", meant: "i ate the whole pie", wrong: "hole", right: "whole"),
        Case(heard: "dig a whole here", meant: "dig a hole here", wrong: "whole", right: "hole"),
        Case(
            heard: "the school principle spoke", meant: "the school principal spoke", wrong: "principle",
            right: "principal"),
        Case(
            heard: "it is a matter of principal", meant: "it is a matter of principle", wrong: "principal",
            right: "principle"),
        Case(
            heard: "the beam is made of steal", meant: "the beam is made of steel", wrong: "steal",
            right: "steel"),
        Case(heard: "do not steel the car", meant: "do not steal the car", wrong: "steel", right: "steal"),
        Case(heard: "the plain landed late", meant: "the plane landed late", wrong: "plain", right: "plane"),
        Case(heard: "a plane white shirt", meant: "a plain white shirt", wrong: "plane", right: "plain"),
        Case(heard: "she road the bus home", meant: "she rode the bus home", wrong: "road", right: "rode"),
        Case(heard: "the rode was closed", meant: "the road was closed", wrong: "rode", right: "road"),
    ]

    /// What happened to one sentence at one score.
    struct Cell: Equatable {
        let offered: Bool
        let refused: Bool
    }

    /// The draft with only the misheard word scored `score`, everything else heard surely.
    static func draft(_ item: Case, wrongAt score: Double) -> Draft {
        let words = item.heard.split(separator: " ").map(String.init)
        let wrongIndex = words.lastIndex(of: item.wrong)
        return Draft(
            words: words.indices.map {
                Draft.Word(words[$0], evidence: .score($0 == wrongIndex ? score : 0.95))
            })
    }

    /// Asks the shipping sources whether the meant word is offered, then judges the rewrite that takes it.
    static func cell(_ item: Case, at score: Double) async -> Cell {
        let draft = draft(item, wrongAt: score)
        let spans = await DoubtfulWords.standard.spans(in: draft, for: .unknown)
        let offered = spans.contains { span in
            span.heard == item.wrong && span.candidates.contains { $0.spelling == item.right }
        }
        let verdict = MeaningPreservationGuard().verdict(draft: draft, rewritten: item.meant, offering: spans)
        return Cell(offered: offered, refused: !verdict.isAccepted)
    }

    @Test("records how many cells offer the meant word and then refuse the rewrite that takes it")
    func offeredThenRefused() async {
        var table: [String] = []
        var offeredThenRefused = 0
        var offered = 0
        for (group, cases) in [("function", Self.functionWordCases), ("sense", Self.senseCases)] {
            for score in Self.scores {
                var groupOffered = 0
                var groupRefused = 0
                for item in cases {
                    let cell = await Self.cell(item, at: score)
                    groupOffered += cell.offered ? 1 : 0
                    groupRefused += cell.offered && cell.refused ? 1 : 0
                }
                offered += groupOffered
                offeredThenRefused += groupRefused
                table.append(
                    "\(group) \(score): offered \(groupOffered)/20, offered then refused \(groupRefused)")
            }
        }
        print(table.joined(separator: "\n"))
        #expect(offered == Self.expectedOffered)
        #expect(offeredThenRefused == Self.expectedOfferedThenRefused)
    }

    /// Measured on the shipping sources and guard: a reading the guard would refuse is never offered.
    static let expectedOffered = 105
    static let expectedOfferedThenRefused = 0
}
