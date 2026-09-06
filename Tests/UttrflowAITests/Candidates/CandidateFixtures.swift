import UttrflowCore

@testable import UttrflowAI

/// A source that answers with whatever a test scripted, for every word it is asked about.
struct ScriptedCandidates: CandidateSource {
    let answers: [String: [String]]

    init(_ answers: [String: [String]]) {
        self.answers = answers
    }

    func candidates(for word: Draft.Word, in situation: Situation) async -> [String] {
        answers[word.text] ?? []
    }
}

/// The line every source has to reach before any of them may answer, so a serial caller is caught.
actor StartLine {
    /// Enough turns for the other sources to arrive, and few enough that a serial caller gives up quickly.
    static let attempts = 10_000

    private let expected: Int
    private var arrived = 0

    init(expected: Int) {
        self.expected = expected
    }

    /// Whether everybody arrived, which only happens when the sources run beside each other.
    func waitForEverybody() async -> Bool {
        arrived += 1
        for _ in 0..<Self.attempts {
            if arrived >= expected { return true }
            await Task.yield()
        }
        return false
    }
}

/// A source that answers only once every other source has been asked.
struct BarrierCandidates: CandidateSource {
    let line: StartLine
    let answer: String

    func candidates(for word: Draft.Word, in situation: Situation) async -> [String] {
        await line.waitForEverybody() ? [answer] : []
    }
}

extension Draft {
    /// A draft written as a sentence, where a leading `?` marks a word the recogniser was unsure of.
    static func heard(_ text: String, unsure: Double = 0.3) -> Draft {
        Draft(
            words: text.split(whereSeparator: \.isWhitespace).map {
                $0.hasPrefix("?")
                    ? Draft.Word(String($0.dropFirst()), confidence: unsure)
                    : Draft.Word(String($0), confidence: 0.95)
            },
            confidencesAreReal: true)
    }
}

extension Situation {
    /// A situation showing exactly the window title, selection and caret text a test wants read.
    static func showing(
        title: String? = nil, selection: String? = nil, preceding: String? = nil,
        following: String? = nil
    ) -> Situation {
        let app = AppContext(
            documentName: title, selectedText: selection, precedingText: preceding,
            followingText: following)
        return Situation(app: app, insertion: app.insertionPoint, destination: .plain)
    }
}
