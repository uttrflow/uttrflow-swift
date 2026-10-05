// Invented cases tagged by formatting class, so every class in the coverage matrix has a floor of evidence.
import UttrflowCore

extension EvaluationCorpus {
    // MARK: Formatting classes. See Docs/formatting-matrix.md.

    static let formatting: [EvaluationCase] =
        boundaryCases + commaCases + questionCases + quoteCases + ellipsisCases + tokenCases
        + numberCases + listCases + paragraphCases + correctionCases + destinationCases + codeCases
        + hinglishCases + probeCases + followingTextCases + casingCases

    static let casingCases: [EvaluationCase] = [
        .init(
            id: "fmt-casing-use-word", category: .everyday,
            spoken: "the office will be all caps closed on monday",
            expected: "The office will be CLOSED on Monday.",
            mustKeep: ["CLOSED", "Monday"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-use-two", category: .everyday,
            spoken: "the office will be all caps closed and parking is all caps not available",
            expected: "The office will be CLOSED and parking is NOT available.",
            mustKeep: ["CLOSED", "NOT"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-use-urgent", category: .everyday,
            spoken: "all caps urgent the server is down",
            expected: "URGENT the server is down.",
            mustKeep: ["URGENT", "server"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-use-before-words", category: .everyday,
            spoken: "this is all caps important for everyone",
            expected: "This is IMPORTANT for everyone.",
            mustKeep: ["IMPORTANT", "everyone"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-use-word-ends-sentence", category: .everyday,
            spoken: "please do all caps not",
            expected: "Please do NOT.",
            mustKeep: ["NOT"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-use-span", category: .everyday,
            spoken: "all caps on do not enter all caps off without a badge",
            expected: "DO NOT ENTER without a badge.",
            mustKeep: ["DO", "ENTER", "badge"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-use-span-mid", category: .everyday,
            spoken: "the sign says all caps on wet floor all caps off near the door",
            expected: "The sign says WET FLOOR near the door.",
            mustKeep: ["WET", "FLOOR", "door"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-use-span-one-word", category: .everyday,
            spoken: "we are all caps on open all caps off today",
            expected: "We are OPEN today.",
            mustKeep: ["OPEN", "today"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-the-rule", category: .everyday,
            spoken: "the all caps rule applies to headings",
            expected: "The all caps rule applies to headings.",
            mustKeep: ["all", "caps", "rule"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-subject", category: .everyday,
            spoken: "all caps is shouting",
            expected: "All caps is shouting.",
            mustKeep: ["caps", "shouting"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-in", category: .everyday,
            spoken: "she wrote the title in all caps",
            expected: "She wrote the title in all caps.",
            mustKeep: ["all", "caps"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-in-before-word", category: .everyday,
            spoken: "type it in all caps please",
            expected: "Type it in all caps please.",
            mustKeep: ["all", "caps", "please"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-use", category: .everyday,
            spoken: "never use all caps headings",
            expected: "Never use all caps headings.",
            mustKeep: ["caps", "headings"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-was", category: .everyday,
            spoken: "all caps was the old style",
            expected: "All caps was the old style.",
            mustKeep: ["caps", "old"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-no", category: .everyday,
            spoken: "there are no all caps titles here",
            expected: "There are no all caps titles here.",
            mustKeep: ["caps", "titles"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-mention-of", category: .everyday,
            spoken: "the problem of all caps text",
            expected: "The problem of all caps text.",
            mustKeep: ["caps", "text"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-span-without-off", category: .everyday,
            spoken: "all caps on the shelf",
            expected: "All caps on the shelf.",
            mustKeep: ["caps", "shelf"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-command-alone", category: .everyday,
            spoken: "make it all caps",
            expected: "Make it all caps.",
            mustKeep: ["all", "caps"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-not-capital-gains", category: .everyday,
            spoken: "capital gains tax is due in april",
            expected: "Capital gains tax is due in April.",
            mustKeep: ["Capital", "gains"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-not-capital-of", category: .everyday,
            spoken: "the capital of france is paris",
            expected: "The capital of France is Paris.",
            mustKeep: ["capital", "France"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-casing-not-no-caps-bottles", category: .everyday,
            spoken: "there are no caps on the bottles",
            expected: "There are no caps on the bottles.",
            mustKeep: ["caps", "bottles"], classes: [.capitalisationAndTokens]
        ),
    ]

    static let boundaryCases: [EvaluationCase] = [
        .init(
            id: "fmt-boundary-two-statements", category: .everyday,
            spoken: "the kettle is broken we need a new one",
            expected: "The kettle is broken. We need a new one.",
            mustKeep: ["kettle", "new"], classes: [.sentenceBoundaries]
        ),
        .init(
            id: "fmt-boundary-run-on-three", category: .everyday,
            spoken: "the bus was late the train was cancelled we walked home",
            expected: "The bus was late. The train was cancelled. We walked home.",
            mustKeep: ["bus", "train", "walked"], classes: [.sentenceBoundaries]
        ),
        .init(
            id: "fmt-boundary-stray-stop-mid-clause", category: .everyday,
            spoken: "Please water the. Plants on the balcony",
            expected: "Please water the plants on the balcony.",
            mustKeep: ["water", "balcony"], classes: [.sentenceBoundaries]
        ),
        .init(
            id: "fmt-boundary-single-word", category: .everyday,
            spoken: "done",
            expected: "Done.",
            mustKeep: ["Done"], classes: [.sentenceBoundaries]
        ),
        // Adversarial: "so" opens a clause here, and no stop belongs before it.
        .init(
            id: "fmt-boundary-so-joins-clause", category: .everyday,
            spoken: "it was raining so we stayed inside",
            expected: "It was raining, so we stayed inside.",
            mustKeep: ["raining", "stayed"], mustNotAdd: ["raining. So"],
            classes: [.sentenceBoundaries, .commas]
        ),
    ]

    static let commaCases: [EvaluationCase] = [
        .init(
            id: "fmt-comma-vocative", category: .everyday,
            spoken: "thanks Tomas see you tomorrow",
            expected: "Thanks, Tomas. See you tomorrow.",
            mustKeep: ["Tomas", "tomorrow"], classes: [.commas]
        ),
        .init(
            id: "fmt-comma-introductory", category: .everyday,
            spoken: "however the venue is still free",
            expected: "However, the venue is still free.",
            mustKeep: ["However", "venue"], classes: [.commas]
        ),
        .init(
            id: "fmt-comma-but-clause", category: .everyday,
            spoken: "I called twice but nobody answered",
            expected: "I called twice, but nobody answered.",
            mustKeep: ["called", "nobody"], classes: [.commas]
        ),
        .init(
            id: "fmt-comma-yes-answer", category: .everyday,
            spoken: "yes that works for me",
            expected: "Yes, that works for me.",
            mustKeep: ["Yes", "works"], classes: [.commas]
        ),
        // Adversarial: a short restrictive clause takes no comma.
        .init(
            id: "fmt-comma-none-in-short-clause", category: .everyday,
            spoken: "the book that I lent you is overdue",
            expected: "The book that I lent you is overdue.",
            mustKeep: ["book", "overdue"], mustNotAdd: ["book, that"], classes: [.commas]
        ),
    ]

    static let questionCases: [EvaluationCase] = [
        .init(
            id: "fmt-question-can-you", category: .everyday,
            spoken: "can you send me the file",
            expected: "Can you send me the file?",
            mustKeep: ["send", "file"], mustEndWith: "?", classes: [.questions]
        ),
        .init(
            id: "fmt-question-what-time", category: .everyday,
            spoken: "what time does the shop open",
            expected: "What time does the shop open?",
            mustKeep: ["time", "shop"], mustEndWith: "?", classes: [.questions]
        ),
        .init(
            id: "fmt-question-after-statement", category: .everyday,
            spoken: "the room is booked do you need a projector",
            expected: "The room is booked. Do you need a projector?",
            mustKeep: ["booked", "projector"], mustEndWith: "?", classes: [.questions, .sentenceBoundaries]
        ),
        .init(
            id: "fmt-question-tag", category: .everyday,
            spoken: "the meeting is at three isn't it",
            expected: "The meeting is at 3, isn't it?",
            mustKeep: ["meeting", "isn't"], mustEndWith: "?", classes: [.questions]
        ),
        // Adversarial: an indirect question is a statement and keeps its stop.
        .init(
            id: "fmt-question-indirect-is-statement", category: .everyday,
            spoken: "I wonder where the keys are",
            expected: "I wonder where the keys are.",
            mustKeep: ["wonder", "keys"], mustEndWith: ".", classes: [.questions]
        ),
    ]

    static let quoteCases: [EvaluationCase] = [
        .init(
            id: "fmt-quote-said", category: .everyday,
            spoken: "she said quote see you at noon end quote",
            expected: "She said \"see you at noon\".",
            mustKeep: ["see", "noon"], mustNotAdd: ["quote"], classes: [.quotesAndBrackets]
        ),
        .init(
            id: "fmt-quote-open-close", category: .everyday,
            spoken: "the sign read open quote closed for lunch close quote",
            expected: "The sign read \"closed for lunch\".",
            mustKeep: ["sign", "lunch"], classes: [.quotesAndBrackets]
        ),
        .init(
            id: "fmt-quote-nested", category: .everyday,
            spoken:
                "she said open quote he wrote open single quote done close single quote on the board close quote and left",
            expected: "She said \"he wrote 'done' on the board\" and left.",
            mustKeep: ["wrote", "board"], classes: [.quotesAndBrackets]
        ),
        .init(
            id: "fmt-bracket-aside", category: .everyday,
            spoken: "bring a jacket open bracket it gets cold close bracket",
            expected: "Bring a jacket (it gets cold).",
            mustKeep: ["jacket", "cold"], classes: [.quotesAndBrackets]
        ),
        .init(
            id: "fmt-paren-aside", category: .everyday,
            spoken: "the report open paren draft two close paren is attached",
            expected: "The report (draft 2) is attached.",
            mustKeep: ["report", "attached"], classes: [.quotesAndBrackets]
        ),
        // Adversarial: "quote" as a noun is a word, not a mark.
        .init(
            id: "fmt-quote-noun-stays", category: .everyday,
            spoken: "the builder sent a quote for the roof",
            expected: "The builder sent a quote for the roof.",
            mustKeep: ["quote", "roof"], mustNotAdd: ["\""], classes: [.quotesAndBrackets]
        ),
    ]

    static let ellipsisCases: [EvaluationCase] = [
        .init(
            id: "fmt-ellipsis-spoken-dot-dot-dot", category: .everyday,
            spoken: "and then dot dot dot nothing happened",
            expected: "And then... nothing happened.",
            mustKeep: ["then", "nothing"], classes: [.ellipses]
        ),
        .init(
            id: "fmt-ellipsis-named", category: .everyday,
            spoken: "wait for it ellipsis",
            expected: "Wait for it...",
            mustKeep: ["Wait"], mustNotAdd: ["ellipsis"], classes: [.ellipses]
        ),
        .init(
            id: "fmt-ellipsis-from-recogniser", category: .everyday,
            spoken: "I thought... maybe tomorrow",
            expected: "I thought... maybe tomorrow.",
            mustKeep: ["thought", "tomorrow"], classes: [.ellipses]
        ),
        .init(
            id: "fmt-ellipsis-trailing-off", category: .everyday,
            spoken: "well if you insist...",
            expected: "Well, if you insist...",
            mustKeep: ["insist"], mustEndWith: "...", classes: [.ellipses]
        ),
        // Adversarial: a pause is not an ellipsis, and none is invented.
        .init(
            id: "fmt-ellipsis-not-invented", category: .everyday,
            spoken: "the parcel arrived this morning",
            expected: "The parcel arrived this morning.",
            mustKeep: ["parcel", "morning"], mustNotAdd: ["..."], classes: [.ellipses]
        ),
    ]

    static let tokenCases: [EvaluationCase] = [
        .init(
            id: "fmt-token-pronoun-i", category: .everyday,
            spoken: "i think i left it at home",
            expected: "I think I left it at home.",
            mustKeep: ["think", "home"], mustBeginWith: "I think I", classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-token-email-address", category: .technical,
            spoken: "write to help at example dot com",
            expected: "Write to help@example.com.",
            mustKeep: ["help@example.com"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-token-web-address", category: .technical,
            spoken: "the page is at docs dot example dot com slash setup",
            expected: "The page is at docs.example.com/setup.",
            mustKeep: ["docs.example.com/setup"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-token-web-path-stopped", category: .technical,
            spoken: "Visit example dot com slash pricing.",
            expected: "Visit example.com/pricing.",
            mustKeep: ["example.com/pricing"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-token-web-deep-path-stopped", category: .technical,
            spoken: "The site is example dot org slash docs slash intro.",
            expected: "The site is example.org/docs/intro.",
            mustKeep: ["example.org/docs/intro"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-token-url-path-stopped", category: .technical,
            spoken: "The url is https colon slash slash example dot com slash docs.",
            expected: "The url is https:\u{2F}\u{2F}example.com/docs.",
            mustKeep: ["https:\u{2F}\u{2F}example.com/docs"], classes: [.capitalisationAndTokens]
        ),
        .init(
            id: "fmt-token-acronym-kept", category: .technical,
            spoken: "the API returns JSON",
            expected: "The API returns JSON.",
            mustKeep: ["API", "JSON"], classes: [.capitalisationAndTokens]
        ),
        // Adversarial: a brand that opens in lowercase keeps its own casing.
        .init(
            id: "fmt-token-mixed-case-brand", category: .technical,
            spoken: "we moved the repo to iCloud drive",
            expected: "We moved the repo to iCloud drive.",
            mustKeep: ["iCloud"], classes: [.capitalisationAndTokens]
        ),
    ]

    static let numberCases: [EvaluationCase] = [
        .init(
            id: "fmt-number-count", category: .everyday,
            spoken: "we need twelve chairs",
            expected: "We need 12 chairs.",
            mustKeep: ["12", "chairs"], classes: [.numbers], semiotic: .cardinal
        ),
        .init(
            id: "fmt-number-percent", category: .everyday,
            spoken: "sales grew by fifteen percent",
            expected: "Sales grew by 15%.",
            mustKeep: ["15%"], classes: [.numbers], semiotic: .measure
        ),
        .init(
            id: "fmt-number-time", category: .everyday,
            spoken: "the call is at four thirty",
            expected: "The call is at 4:30.",
            mustKeep: ["call"], classes: [.numbers], semiotic: .time
        ),
        .init(
            id: "fmt-number-money", category: .everyday,
            spoken: "the ticket costs forty dollars",
            expected: "The ticket costs 40 dollars.",
            mustKeep: ["ticket", "40"], classes: [.numbers], semiotic: .money
        ),
        // Adversarial: "one" as a pronoun is a word, not a numeral.
        .init(
            id: "fmt-number-one-as-pronoun", category: .everyday,
            spoken: "this one is better",
            expected: "This one is better.",
            mustKeep: ["one", "better"], mustNotAdd: ["1"], classes: [.numbers], semiotic: .staysWords
        ),
    ]

    static let listCases: [EvaluationCase] = [
        .init(
            id: "fmt-list-numbered-spoken", category: .everyday,
            spoken: "one milk two eggs three bread",
            expected: "1. Milk\n2. Eggs\n3. Bread",
            mustKeep: ["Milk", "Eggs", "Bread"], classes: [.lists]
        ),
        .init(
            id: "fmt-list-first-second-third", category: .everyday,
            spoken: "first book the hall second send invites third order food",
            expected: "1. Book the hall\n2. Send invites\n3. Order food",
            mustKeep: ["hall", "invites", "food"], classes: [.lists]
        ),
        .init(
            id: "fmt-list-inline-series", category: .everyday,
            spoken: "pack socks shirts and a towel",
            expected: "Pack socks, shirts and a towel.",
            mustKeep: ["socks", "shirts", "towel"], classes: [.lists, .commas]
        ),
        .init(
            id: "fmt-list-bullet-command", category: .everyday,
            spoken: "bullet point call the plumber bullet point pay the rent",
            expected: "- Call the plumber\n- Pay the rent",
            mustKeep: ["plumber", "rent"], mustNotAdd: ["bullet"], classes: [.lists]
        ),
        .init(
            id: "fmt-list-lead-in-document", category: .everyday,
            spoken: "the steps are as follows back up the files",
            expected: "The steps are as follows: back up the files.",
            mustKeep: ["as follows:", "back up"],
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, classes: [.lists, .perDestination]
        ),
        .init(
            id: "fmt-list-lead-in-email", category: .everyday,
            spoken: "the agenda is as follows the budget review",
            expected: "The agenda is as follows: the budget review.",
            mustKeep: ["as follows:", "budget"],
            context: AppContext(applicationName: "Mail", bundleIdentifier: "com.apple.mail"),
            destination: .email, classes: [.lists, .perDestination]
        ),
        .init(
            id: "fmt-list-lead-in-chat", category: .everyday,
            spoken: "the plan is as follows lunch at noon",
            expected: "The plan is as follows: lunch at noon",
            mustKeep: ["as follows:", "lunch"],
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            mustNotAdd: ["."], destination: .messaging, classes: [.lists, .perDestination]
        ),
        // Adversarial: with no lead-in, ordinals in a clause get no colon.
        .init(
            id: "fmt-list-no-lead-in-no-colon", category: .everyday,
            spoken: "the steps are first and second",
            expected: "The steps are first and second.",
            mustKeep: ["steps are first"], mustNotAdd: [":"], classes: [.lists]
        ),
        // Adversarial: counting inside a sentence is not a list.
        .init(
            id: "fmt-list-count-not-list", category: .everyday,
            spoken: "I have two cats and three dogs",
            expected: "I have 2 cats and 3 dogs.",
            mustKeep: ["cats", "dogs"], mustNotAdd: ["\n"], classes: [.lists, .numbers]
        ),
    ]

    static let paragraphCases: [EvaluationCase] = [
        .init(
            id: "fmt-paragraph-new-paragraph", category: .everyday,
            spoken: "the trip is booked new paragraph the hotel is near the station",
            expected: "The trip is booked.\n\nThe hotel is near the station.",
            mustKeep: ["trip", "hotel"], mustNotAdd: ["paragraph"], classes: [.paragraphs]
        ),
        .init(
            id: "fmt-paragraph-new-line", category: .everyday,
            spoken: "dear team new line the office is closed on friday",
            expected: "Dear team\nThe office is closed on Friday.",
            mustKeep: ["team", "office"], mustNotAdd: ["new line"], classes: [.paragraphs]
        ),
        .init(
            id: "fmt-paragraph-two-breaks", category: .everyday,
            spoken: "first point new paragraph second point new paragraph last point",
            expected: "First point.\n\nSecond point.\n\nLast point.",
            mustKeep: ["Second", "Last"], mustNotAdd: ["paragraph"], classes: [.paragraphs]
        ),
        .init(
            id: "fmt-paragraph-next-line", category: .everyday,
            spoken: "regards next line Sam",
            expected: "Regards\nSam",
            mustKeep: ["Regards", "Sam"], classes: [.paragraphs]
        ),
        // Adversarial: "a new paragraph" as an object is words, not a break.
        .init(
            id: "fmt-paragraph-noun-stays", category: .everyday,
            spoken: "I added a new paragraph about pricing",
            expected: "I added a new paragraph about pricing.",
            mustKeep: ["paragraph", "pricing"], mustNotAdd: ["\n"], classes: [.paragraphs]
        ),
    ]

    static let correctionCases: [EvaluationCase] = [
        .init(
            id: "fmt-correction-no-wait", category: .everyday,
            spoken: "meet at the library no wait at the cafe",
            expected: "Meet at the cafe.",
            mustKeep: ["cafe"], mustNotAdd: ["library"], classes: [.corrections]
        ),
        .init(
            id: "fmt-correction-i-mean", category: .everyday,
            spoken: "send it on Tuesday I mean Wednesday",
            expected: "Send it on Wednesday.",
            mustKeep: ["Wednesday"], mustNotAdd: ["Tuesday"], classes: [.corrections]
        ),
        .init(
            id: "fmt-correction-actually", category: .everyday,
            spoken: "we need five boxes actually six boxes",
            expected: "We need 6 boxes.",
            mustKeep: ["boxes"], classes: [.corrections, .numbers]
        ),
        .init(
            id: "fmt-correction-stammer", category: .everyday,
            spoken: "the the report is is ready",
            expected: "The report is ready.",
            mustKeep: ["report", "ready"], classes: [.corrections]
        ),
        // Adversarial: "I mean it" is meant, not a correction.
        .init(
            id: "fmt-correction-i-mean-it-stays", category: .everyday,
            spoken: "please be on time I mean it",
            expected: "Please be on time. I mean it.",
            mustKeep: ["time", "mean"], classes: [.corrections]
        ),
    ]

    static let destinationCases: [EvaluationCase] = [
        .init(
            id: "fmt-destination-messaging-no-stop", category: .everyday,
            spoken: "on my way",
            expected: "On my way",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            mustNotAdd: ["."], destination: .messaging, mustEndWith: "way",
            classes: [.perDestination]
        ),
        .init(
            id: "fmt-destination-terminal-command", category: .everyday,
            spoken: "cd projects",
            expected: "cd projects",
            context: AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            mustNotAdd: ["."], destination: .terminal, mustBeginWith: "cd", mustEndWith: "projects",
            classes: [.perDestination]
        ),
        .init(
            id: "fmt-destination-spreadsheet-cell", category: .everyday,
            spoken: "rent",
            expected: "rent",
            context: AppContext(applicationName: "Numbers", bundleIdentifier: "com.apple.iWork.Numbers"),
            mustNotAdd: ["."], destination: .spreadsheet, mustBeginWith: "rent",
            classes: [.perDestination]
        ),
        .init(
            id: "fmt-destination-email-sentence", category: .everyday,
            spoken: "the invoice is attached",
            expected: "The invoice is attached.",
            context: AppContext(applicationName: "Mail", bundleIdentifier: "com.apple.mail"),
            destination: .email, mustEndWith: "attached.",
            classes: [.perDestination]
        ),
        .init(
            id: "fmt-destination-document-sentence", category: .everyday,
            spoken: "the results are below",
            expected: "The results are below.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustEndWith: "below.",
            classes: [.perDestination]
        ),
    ]

    static let codeCases: [EvaluationCase] = [
        .init(
            id: "fmt-code-snake-case", category: .technical,
            spoken: "rename user_id to account_id",
            expected: "Rename user_id to account_id.",
            mustKeep: ["user_id", "account_id"], classes: [.codeAndMarkdown]
        ),
        .init(
            id: "fmt-code-camel-case", category: .technical,
            spoken: "call fetchOrders before render",
            expected: "Call fetchOrders before render.",
            mustKeep: ["fetchOrders"], classes: [.codeAndMarkdown]
        ),
        .init(
            id: "fmt-code-file-name", category: .technical,
            spoken: "open README.md and package.json",
            expected: "Open README.md and package.json.",
            mustKeep: ["README.md", "package.json"], classes: [.codeAndMarkdown]
        ),
        .init(
            id: "fmt-code-version", category: .technical,
            spoken: "upgrade to version 2.4.1",
            expected: "Upgrade to version 2.4.1.",
            mustKeep: ["2.4.1"], classes: [.codeAndMarkdown]
        ),
        // Adversarial: markdown a speaker typed stays as typed.
        .init(
            id: "fmt-code-markdown-heading-kept", category: .technical,
            spoken: "# Release notes",
            expected: "# Release notes",
            mustKeep: ["#", "Release"], classes: [.codeAndMarkdown]
        ),
    ]

    static let hinglishCases: [EvaluationCase] = [
        .init(
            id: "fmt-hinglish-question", category: .multilingual, language: .hindi,
            spoken: "क्या तुम कल office आओगे",
            expected: "Kya tum kal office aaoge?",
            mustKeep: ["office"], mustEndWith: "?", classes: [.hinglish, .questions]
        ),
        .init(
            id: "fmt-hinglish-statement", category: .multilingual, language: .hindi,
            spoken: "मैं report भेज दूंगा",
            expected: "Main report bhej dunga.",
            mustKeep: ["report"], classes: [.hinglish]
        ),
        .init(
            id: "fmt-hinglish-number", category: .multilingual, language: .hindi,
            spoken: "हमें दस chairs चाहिए",
            expected: "Humein 10 chairs chahiye.",
            mustKeep: ["chairs"], classes: [.hinglish, .numbers]
        ),
        .init(
            id: "fmt-hinglish-two-sentences", category: .multilingual, language: .hindi,
            spoken: "train late है मैं बाद में call करूंगा",
            expected: "Train late hai. Main baad mein call karunga.",
            mustKeep: ["train", "call"], classes: [.hinglish, .sentenceBoundaries]
        ),
        // Adversarial: already romanised Hinglish is left in Latin letters and never translated.
        .init(
            id: "fmt-hinglish-already-latin", category: .multilingual, language: .hindi,
            spoken: "kal milte hain",
            expected: "Kal milte hain.",
            mustKeep: ["milte"], mustNotAdd: ["tomorrow"], classes: [.hinglish]
        ),
    ]
}
