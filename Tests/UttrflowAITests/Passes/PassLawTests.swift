import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowAI

/// Every pass the shipped pipelines run, each once, so a pass that states its laws is checked against them.
private let everyPass: [any CleaningPass] = {
    let pipelines = [
        CleaningPipeline.standard,
        .standard(for: .standard(for: .codeEditor), situation: .unknown),
        .afterModelPiece(digits: .thousands, situation: .unknown),
    ]
    var seen: Set<PassID> = []
    // Code commands run only with the caret in code, spoken emoji only when the user turns them on, at-mentions only in chat.
    let offByDefault: [any CleaningPass] = [
        CodeEditorCommandsPass(), SpokenEmojiPass(destination: .plain), AtMentionPass(precedingText: nil),
    ]
    return (pipelines.flatMap(\.passes) + offByDefault).filter { seen.insert($0.id).inserted }
}()

/// Words a dictation is made of: fillers, spoken marks and layout, numbers, Hindi romanised, corrections and letters.
private let vocabulary = [
    "um", "uh", "so", "like", "I", "mean", "no", "wait", "actually", "the", "the", "meeting", "is", "at",
    "comma", "period", "full", "stop", "question", "mark", "new", "line", "paragraph", "bullet", "point",
    "one", "two", "three", "twenty", "five", "hundred", "thousand", "point", "percent", "dollars",
    "42", "10000", "3.5", "2024", ",", ".", "?", "-", "do", "not", "it", "will", "we", "are",
    "haan", "nahi", "accha", "theek", "hai", "kya", "a", "p", "i", "API", "OK", "monday", "Delhi",
]

/// One generated dictation: up to sixteen words, a word sometimes said twice the way a stammer is.
private func dictation(_ random: inout Seeded) -> [String] {
    var words: [String] = []
    for _ in 0..<Int.random(in: 1...16, using: &random) {
        let word = random.pick(vocabulary)
        words.append(word)
        if random.chance(0.1) { words.append(word) }
    }
    return words
}

/// The words of a text, lower-cased and cut at anything that is not a letter.
private func letterWords(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter }.map(String.init)
}

/// Whether the pass keeps the law on this input.
private func keeps(_ law: PassLaw, _ pass: any CleaningPass, on words: [String]) -> Bool {
    let input = words.joined(separator: " ")
    let once = pass.apply(Draft(text: input))
    switch law {
    case .idempotent:
        return pass.apply(once).text == once.text
    case .addsNoWords:
        return Set(letterWords(once.text)).isSubset(of: Set(letterWords(input)))
    case .keepsDigits:
        return once.text.filter(\.isNumber) == input.filter(\.isNumber)
    case .latinOnly:
        return !once.text.unicodeScalars.contains {
            (0x0900...0x097F).contains($0.value) || ($0.properties.generalCategory == .control && $0 != "\n")
        }
    }
}

/// The shortest input found by dropping one word at a time that still breaks the law.
private func shrunk(_ words: [String], _ law: PassLaw, _ pass: any CleaningPass) -> [String] {
    var current = words
    var index = 0
    while index < current.count {
        var smaller = current
        smaller.remove(at: index)
        if !smaller.isEmpty, !keeps(law, pass, on: smaller) { current = smaller } else { index += 1 }
    }
    return current
}

@Suite("Every cleaning pass keeps the laws it states")
struct PassLawTests {
    @Test("the suite covers every pass the shipped pipelines run")
    func coversEveryPass() {
        #expect(everyPass.count == 23)
    }

    @Test("each stated law holds on generated dictation", arguments: PassLaw.allCases)
    func lawHolds(_ law: PassLaw) {
        for pass in everyPass where pass.laws.contains(law) {
            for seed in Seeded.seeds(0..<300) {
                var random = Seeded(seed: seed)
                let words = dictation(&random)
                guard !keeps(law, pass, on: words) else { continue }
                let smallest = shrunk(words, law, pass).joined(separator: " ")
                Issue.record("\(pass.id) breaks \(law) at \(random): \"\(smallest)\"")
                break
            }
        }
    }

    @Test("a pass that is not idempotent is caught and shrunk to one word")
    func catchesBrokenPass() {
        let words = ["the", "meeting", "is"]
        #expect(!keeps(.idempotent, DoublingPass(), on: words))
        #expect(shrunk(words, .idempotent, DoublingPass()).count == 1)
    }
}

/// Writes the first word twice, so each run adds another copy.
private struct DoublingPass: PieceCleaningPass {
    static let id: PassID = "doubling"
    static let laws: Set<PassLaw> = [.idempotent]
    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        if let first = draft.presentIndices.first {
            let word = draft.words[first].text
            draft.replace(at: first, with: word + " " + word, by: Self.id)
        }
        return draft
    }
}
