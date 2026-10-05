// Invented dictations, each naming the disfluency it is about, scored by the words deleted.

/// A clean-up case and the disfluency class it is scored under.
public struct DisfluencyCase: Sendable, Equatable {
    public let disfluency: DisfluencyClass
    public let evaluation: EvaluationCase

    init(_ disfluency: DisfluencyClass, _ id: String, _ spoken: String, _ expected: String) {
        self.disfluency = disfluency
        evaluation = EvaluationCase(id: "disfluency-\(id)", category: .everyday, spoken: spoken, expected: expected)
    }
}

extension EvaluationCorpus {
    // MARK: Disfluency deletion. See Docs/disfluency-deletion.md.

    /// Every disfluency case; the expected text keeps every word a fluent reading keeps and nothing else.
    public static let disfluency: [DisfluencyCase] = [
        .init(.filledPause, "um-opening", "um the report is ready", "The report is ready."),
        .init(.filledPause, "uh-middle", "we can uh ship it on friday", "We can ship it on Friday."),
        .init(.filledPause, "two-sounds", "the build uh failed um again", "The build failed again."),
        .init(.filledPause, "hmm-before-answer", "hmm the meeting moved to noon", "The meeting moved to noon."),
        .init(.filledPause, "er-before-verb", "the client er approved the draft", "The client approved the draft."),
        .init(.filledPause, "beside-number", "set the timer for uh ten minutes", "Set the timer for ten minutes."),
        .init(.filledPause, "between-numbers", "we need five um six chairs", "We need five six chairs."),
        .init(.filledPause, "hinglish-umm", "umm matlab woh file bhej do", "Matlab woh file bhej do."),
        .init(.filledPause, "hinglish-uh-after-haan", "haan uh kal milte hain", "Haan, kal milte hain."),

        .init(.repetition, "doubled-article", "send the the invoice today", "Send the invoice today."),
        .init(.repetition, "doubled-pronoun", "I I think the plan works", "I think the plan works."),
        .init(.repetition, "doubled-phrase", "we were we were waiting for the results", "We were waiting for the results."),
        .init(.repetition, "doubled-preposition", "put it in in the shared folder", "Put it in the shared folder."),
        .init(.repetition, "doubled-to", "we need to to finish the slides", "We need to finish the slides."),
        .init(.repetition, "tripled-article", "the the the report is late", "The report is late."),
        .init(.repetition, "doubled-verb", "is is it ready yet", "Is it ready yet?"),
        .init(.repetition, "doubled-content-word", "the server server crashed again", "The server crashed again."),

        .init(.restart, "phrase-restarted", "can you can you check the logs", "Can you check the logs?"),
        .init(.restart, "clause-restarted", "the server is the server is down again", "The server is down again."),
        .init(.restart, "cut-off-word", "we should rel- release it tomorrow", "We should release it tomorrow."),
        .init(.restart, "opening-restarted", "I want I want to move the call", "I want to move the call."),
        .init(.restart, "question-restarted", "did you did you see the review", "Did you see the review?"),
        .init(.restart, "mid-word-no-hyphen", "the depl deployment failed", "The deployment failed."),
        .init(.restart, "mid-word-send", "can you sen send the file", "Can you send the file?"),
        .init(.restart, "abandoned-noun-phrase", "the meeting the call is at noon", "The call is at noon."),

        .init(.selfRepair, "time", "let's meet at four sorry five", "Let's meet at five."),
        .init(.selfRepair, "colour", "paint the wall blue sorry green", "Paint the wall green."),
        .init(.selfRepair, "day", "the demo is on monday sorry tuesday", "The demo is on Tuesday."),
        .init(.selfRepair, "count", "order three sorry four chairs", "Order four chairs."),
        .init(.selfRepair, "room", "book the north room sorry the south room", "Book the south room."),
        .init(.selfRepair, "filler-before-trigger", "meet at four uh sorry five", "Meet at five."),
        .init(.selfRepair, "bare-no-trigger", "send it to sales no to marketing", "Send it to marketing."),

        .init(.editingPhrase, "scratch-that", "send it to the team scratch that send it to the manager", "Send it to the manager."),
        .init(.editingPhrase, "no-wait", "the flight leaves at six no wait at seven", "The flight leaves at seven."),
        .init(.editingPhrase, "i-mean", "call the bank on monday I mean tuesday", "Call the bank on Tuesday."),
        .init(.editingPhrase, "no-sorry", "we need five copies no sorry ten copies", "We need ten copies."),
        .init(.editingPhrase, "or-rather", "the file is in drafts or rather in archive", "The file is in archive."),
        .init(.editingPhrase, "make-that", "move it to friday actually make that monday", "Move it to Monday."),
        .init(.editingPhrase, "wait-no", "the price is ten dollars wait no twelve dollars", "The price is twelve dollars."),

        .init(.discourseMarker, "so-opening", "so the release is on track", "So the release is on track."),
        .init(.discourseMarker, "well-opening", "well we tried that already", "Well, we tried that already."),
        .init(.discourseMarker, "like-hedge", "it was like a two hour delay", "It was like a two hour delay."),
        .init(.discourseMarker, "you-know", "the budget you know is tight this year", "The budget, you know, is tight this year."),
        .init(.discourseMarker, "basically", "basically the cache was stale", "Basically the cache was stale."),
        .init(.discourseMarker, "like-verb", "I like the new design", "I like the new design."),
        .init(.discourseMarker, "like-comparison", "it looks like rain today", "It looks like rain today."),
        .init(.discourseMarker, "you-know-question", "do you know the answer", "Do you know the answer?"),
        .init(.discourseMarker, "you-know-what", "you know what I mean", "You know what I mean."),
        .init(.discourseMarker, "hinglish-matlab", "haan matlab theek hai", "Haan, matlab theek hai."),

        .init(.fluentControl, "very-very", "the results were very very good", "The results were very very good."),
        .init(.fluentControl, "place-said-twice", "we flew to bora bora last spring", "We flew to Bora Bora last spring."),
        .init(.fluentControl, "had-had", "she had had enough of the delays", "She had had enough of the delays."),
        .init(.fluentControl, "that-that", "he said that that plan was fine", "He said that that plan was fine."),
        .init(.fluentControl, "second-language-phrasing", "I am having two brothers and one sister", "I am having two brothers and one sister."),
        .init(.fluentControl, "no-no", "no no I agree with you", "No, no, I agree with you."),
        .init(.fluentControl, "again-and-again", "we tested it again and again", "We tested it again and again."),
        .init(.fluentControl, "is-is", "what it is is a timing bug", "What it is is a timing bug."),
        .init(.fluentControl, "bye-bye", "bye bye see you tomorrow", "Bye bye, see you tomorrow."),
        .init(.fluentControl, "hinglish-chalo-chalo", "chalo chalo jaldi karo", "Chalo chalo, jaldi karo."),
        .init(.fluentControl, "very-very-very", "it was very very very cold", "It was very very very cold."),
    ]
}
