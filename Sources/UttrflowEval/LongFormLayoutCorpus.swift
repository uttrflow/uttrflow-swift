// Invented dictations of three to eight sentences whose references are laid out in paragraphs or lists.
import UttrflowCore

extension EvaluationCorpus {
    /// Kept out of `all`, so its length does not move the per-case gates sized for single sentences.
    static let longForm: [EvaluationCase] = [
        longFormCase(
            "rambling-email-two-topics",
            "hi priya so the move to the new office is still on for the twentieth and the movers come at eight in the morning please have your desk packed the night before and label every box with your name and floor number new paragraph on a different note the quarterly review moves to thursday the twenty third at two because the board meeting took the tuesday slot and we will use the large room on the fourth floor so bring your slides on a stick in case the screen sharing plays up again thanks owen",
            "Hi Priya, so the move to the new office is still on for the 20th and the movers come at 8 in the morning. Please have your desk packed the night before and label every box with your name and floor number.\n\nOn a different note, the quarterly review moves to Thursday the 23rd at 2 because the board meeting took the Tuesday slot, and we will use the large room on the 4th floor, so bring your slides on a stick in case the screen sharing plays up again. Thanks, Owen",
            keep: ["movers", "review", "slides"], classes: [.paragraphs, .commas, .numbers],
            pausedAfter: [23, 41, 66]),
        longFormCase(
            "hesitating-status-paragraph-at-a-pause",
            "um so the migration ran last night and uh it finished at about three. the row counts match on every table except orders which is short by about forty rows. i think uh those are the test orders we deleted on monday. anyway the second thing is the release. we are still waiting on the signed build from the pipeline and um it should land by noon. once it does i will tag it and send the notes round",
            "So the migration ran last night and it finished at about 3. The row counts match on every table except orders, which is short by about 40 rows. I think those are the test orders we deleted on Monday.\n\nAnyway, the second thing is the release. We are still waiting on the signed build from the pipeline and it should land by noon. Once it does, I will tag it and send the notes round.",
            keep: ["migration", "orders", "release"], classes: [.paragraphs, .numbers, .commas],
            pausedAfter: [13, 29, 41, 48, 66]),
        longFormCase(
            "listing-steps-by-ordinal",
            "to set up the test machine first install the command line tools from the developer site. second clone the repository into your home folder and open a terminal there. third run make bootstrap which fetches the models and builds the app. fourth sign in with the shared test account from the wiki and not your own. finally run make verify and check that every gate passes before you open a pull request and ask in the team channel if anything fails",
            "To set up the test machine:\n1. Install the command line tools from the developer site.\n2. Clone the repository into your home folder and open a terminal there.\n3. Run make bootstrap, which fetches the models and builds the app.\n4. Sign in with the shared test account from the wiki and not your own.\n5. Run make verify and check that every gate passes before you open a pull request, and ask in the team channel if anything fails.",
            keep: ["bootstrap", "repository", "wiki"], classes: [.lists, .paragraphs],
            pausedAfter: [5, 15, 28, 40, 55]),
        longFormCase(
            "correcting-an-item-in-a-list",
            "for the trip we need to pack a few things. bullet point the tent and the two sleeping bags. bullet point the camping stove and enough gas for three nights no actually make that four nights. bullet point the first aid kit and the water filter. bullet point warm layers because it gets cold by the lake after dark. new paragraph i will pick everyone up at seven on saturday so be ready by the door",
            "For the trip we need to pack a few things.\n- The tent and the two sleeping bags.\n- The camping stove and enough gas for four nights.\n- The first aid kit and the water filter.\n- Warm layers, because it gets cold by the lake after dark.\n\nI will pick everyone up at 7 on Saturday, so be ready by the door.",
            keep: ["stove", "four", "filter"], notAdd: ["three"],
            classes: [.lists, .corrections, .paragraphs], pausedAfter: [9, 18, 35, 45, 58]),
        longFormCase(
            "rambling-without-a-pause-past-the-recogniser-window",
            "so what happened at the workshop was that the first speaker ran over by twenty minutes and then the projector in the main hall stopped working. so everyone moved into the smaller room which only had chairs for about thirty people and the rest of us stood at the back for the whole of the second session which was actually the most useful one because it covered the new storage format and the plan for moving the old archives across before the end of the year new paragraph next time we should book the main hall for the whole day and ask for a spare projector",
            "So what happened at the workshop was that the first speaker ran over by 20 minutes and then the projector in the main hall stopped working. So everyone moved into the smaller room, which only had chairs for about 30 people, and the rest of us stood at the back for the whole of the second session, which was actually the most useful one because it covered the new storage format and the plan for moving the old archives across before the end of the year.\n\nNext time we should book the main hall for the whole day and ask for a spare projector.",
            keep: ["workshop", "archives", "spare"], classes: [.paragraphs, .commas, .numbers]),
        longFormCase(
            "eight-sentence-note-with-a-list-and-two-paragraphs",
            "notes from the garden committee meeting. we agreed to move the compost bins to the far corner by the shed because the smell reaches the benches in summer. the water bill came in higher than expected so we will fit a second rain barrel. new paragraph jobs for this month. bullet point mend the gate on the north side. bullet point order mulch for the fruit beds. bullet point paint the shed before the rain sets in. new paragraph the next meeting is on the first wednesday of next month at six thirty in the hall and everyone is welcome to bring a friend",
            "Notes from the garden committee meeting. We agreed to move the compost bins to the far corner by the shed because the smell reaches the benches in summer. The water bill came in higher than expected, so we will fit a second rain barrel.\n\nJobs for this month:\n- Mend the gate on the north side.\n- Order mulch for the fruit beds.\n- Paint the shed before the rain sets in.\n\nThe next meeting is on the first Wednesday of next month at 6:30 in the hall and everyone is welcome to bring a friend.",
            keep: ["compost", "mulch", "Wednesday"],
            classes: [.lists, .paragraphs, .numbers],
            pausedAfter: [5, 27, 43, 49, 58, 66, 76]),
    ]

    /// A long-form case dictated into a document, which is the destination that keeps paragraphs and lists.
    private static func longFormCase(
        _ id: String, _ spoken: String, _ expected: String, keep: [String], notAdd: [String] = [],
        classes: [FormattingClass], pausedAfter: [Int] = []
    ) -> EvaluationCase {
        .init(
            id: "long-form-\(id)", category: .everyday, spoken: spoken, expected: expected, mustKeep: keep,
            mustNotAdd: notAdd, destination: .document, classes: classes, pausedAfter: pausedAfter,
            addedFor: 3585)
    }
}

/// How to speak a long-form case with the system synthesiser: its words, with each pause written as silence.
struct LongFormRecipe: Sendable, Equatable {
    /// Words a minute `say` speaks at its default rate, which the length estimate assumes.
    static let wordsPerMinute = 175.0
    /// The silence written after each paused word, longer than the windowing's sentence pause so a cut can fall there.
    static let pauseSeconds = 1.0

    /// The text handed to `SaySynthesizer`, with `[[slnc]]` commands where the case pauses.
    let script: String
    /// Roughly how long the audio runs, in seconds.
    let estimatedSeconds: Double
    /// The longest run of speech with no written pause, in seconds, which past the recogniser's window forces a cut.
    let longestUnbrokenSeconds: Double

    init(_ testCase: EvaluationCase) {
        let words = WordTokens.words(testCase.spoken, .display)
        let paused = Set(testCase.pausedAfter)
        let silence = "[[slnc \(Int(Self.pauseSeconds * 1000))]]"
        script = words.enumerated().map { paused.contains($0) ? "\($1) \(silence)" : $1 }
            .joined(separator: " ")
        let perWord = 60 / Self.wordsPerMinute
        estimatedSeconds = Double(words.count) * perWord + Double(paused.count) * Self.pauseSeconds
        var longest = 0
        var run = 0
        for index in words.indices {
            run += 1
            longest = max(longest, run)
            if paused.contains(index) { run = 0 }
        }
        longestUnbrokenSeconds = Double(longest) * perWord
    }
}

extension EvaluationCase {
    /// Passes with every reference break and list item in place, no break added, and its kept and barred words honoured.
    func longFormPasses(_ output: String) -> Bool {
        let layout = StructureScore(output: output, for: self)
        let lowered = output.lowercased()
        return layout.correctBreaks == layout.referenceBreaks && layout.outputBreaks == layout.referenceBreaks
            && layout.correctListItems == layout.referenceListItems
            && mustKeep.allSatisfy { output.contains($0) }
            && !mustNotAdd.contains { lowered.contains($0.lowercased()) }
    }
}
