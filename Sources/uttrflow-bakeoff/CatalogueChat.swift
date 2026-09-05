import UttrflowEval
import UttrflowPredict

extension FixtureCatalogue {
    /// Six conversations on screen, each with how this person replies in it; a reply may be anything in register.
    static let chat: [Scenario] = [
        chat(
            "friend", title: "Priya",
            thread: """
                Priya: where did the notarisation log go?
                Me: in dist/, one sec
                Priya: found it, thanks!
                Priya: are you coming tonight?
                Priya: we're at the usual place from 8
                """,
            own: [
                "in dist/, one sec", "on my way", "running late, sorry", "yes!", "save me a seat",
                "be there in 10",
            ],
            lines: [
                Line("on my way", determinacy: .prose), Line("running late, sorry", determinacy: .prose),
                Line("be there in 20", determinacy: .prose), Line("save me a seat", determinacy: .prose),
                "yes, leaving now", "can't make it tonight, sorry", "who else is coming",
                Line("see you at 8", determinacy: .prose), "what's the address again", "order me a beer",
                "haha classic", "sounds good", "give me 15 mins",
            ]),
        chat(
            "hinglish", title: "Rahul", field: "Type a message",
            thread: """
                Rahul: bhai kal free ho?
                Rahul: movie chalte hain
                Me: haan bilkul
                Rahul: kitne baje?
                Rahul: aur khana bhi wahi kha lenge
                """,
            own: [
                "haan bilkul", "theek hai", "kal milte hain", "abhi busy hoon", "chalo done",
                "5 min mein aata hoon",
            ],
            lines: [
                "haan chalo", Line("theek hai bhai", determinacy: .prose),
                Line("kal milte hain", determinacy: .prose),
                "abhi busy hoon, baad mein call karta hoon", "kitne baje milna hai", "mujhe thoda late hoga",
                "khana wahi kha lenge", "ticket book kar diya",
                Line("main nikal raha hoon", determinacy: .prose),
                "ghar pe hoon, aa jao", "acha thik hai", "kal baat karte hain", "haan yaar bilkul",
            ]),
        chat(
            "family", title: "Family",
            thread: """
                Mum: Happy birthday beta! Hope you have a wonderful day
                Papa: Many happy returns of the day
                Mum: call me when you are free
                Mum: did you eat something?
                """,
            own: [
                "love you too", "will call in the evening", "thank you so much!", "yes had lunch",
                "reached safely",
                "talk tonight",
            ],
            lines: [
                Line("thank you so much", determinacy: .prose), Line("love you too", determinacy: .prose),
                Line("will call in the evening", determinacy: .prose), "yes had lunch just now",
                "reached safely, don't worry", "talk tonight after work", "miss you both",
                "send me the recipe",
                "how is dadi feeling", "booked the tickets for diwali", "papa please check your phone",
                "video call on sunday?", "eating well, promise",
            ]),
        chat(
            "work", title: "#platform",
            thread: """
                Neha (PM): Standup moved to 10:30 tomorrow, please confirm.
                Arjun: Confirmed.
                Neha (PM): Also, can someone own the staging deploy this week?
                Arjun: I can take Monday and Tuesday.
                Neha (PM): Thanks. We still need Wednesday to Friday covered.
                """,
            own: [
                "Confirmed, thanks.", "Works for me.", "I will send the numbers after lunch.",
                "Taking a look now.",
                "Deployed to staging, please verify.", "I can cover Wednesday to Friday.",
            ],
            lines: [
                Line("Confirmed, thanks.", determinacy: .prose), "I can cover Wednesday to Friday.",
                Line("Works for me.", determinacy: .prose), Line("Taking a look now.", determinacy: .prose),
                "The deploy is done, please verify.", "Can we move it to 11?",
                "I will send the numbers after lunch.", "Sounds good, added to the calendar.",
                "Rolling back the last release.", "Please review PR 412 when you have a moment.",
                "Standup notes are in the thread.", "I am out tomorrow afternoon.",
                "Let me check with the infra team.",
            ]),
        chat(
            "group", title: "College group", field: "Type a message",
            thread: """
                Rahul: bro the match was insane 🔥🔥
                Amit: last over!! 😱
                Kabir: we have to watch the next one together
                Amit: my place saturday? 🍕
                """,
            own: [
                "haha yes", "count me in", "bro that was wild", "same 😂", "let's gooo 🔥", "bring the snacks",
            ],
            lines: [
                Line("count me in", determinacy: .prose), "haha yes 😂",
                Line("bro that was wild", determinacy: .prose),
                "same bro 😂", "let's gooo 🔥", "bring the snacks 🍕", "what time saturday",
                "i'll get the drinks",
                "cant, exam on monday 😭", "lol what a finish", "book the tickets bro",
                "we should go to the stadium next time", "who is picking me up",
            ]),
        chat(
            "support", title: "Brightleaf Help", field: "Write a message",
            thread: """
                Support bot: Hi! I am the Brightleaf assistant. How can I help today?
                Me: my order hasn't arrived
                Support bot: I am sorry to hear that. Could you share your order number?
                Me: it's order 4471
                Support bot: Thanks. That order shipped on Tuesday and is with the courier. Would you like a refund \
                or a replacement?
                """,
            own: [
                "it's order 4471", "my order hasn't arrived", "a replacement please", "can I talk to a human",
            ],
            lines: [
                Line("a replacement please", determinacy: .prose),
                Line("can I talk to a human", determinacy: .prose),
                "how long will that take", "refund please", "the tracking link doesn't work",
                "I need it before friday", "cancel the order instead",
                "can you resend the confirmation email",
                "the package arrived damaged", "yes that works, thanks", "what is the courier's number",
                "please escalate this", "no thanks, that's all",
            ]),
    ]

    /// A chat: the thread beside the field, how this person replies in it, and its labels and long messages barred.
    static func chat(
        _ name: String, title: String, field: String = "Message", thread: String, own: [String], lines: [Line]
    ) -> Scenario {
        Scenario(
            category: "chat", name: name,
            situation: GenerationSituation(
                application: "Chat", field: field, windowTitle: title, surroundings: thread, recentLines: own,
                isMultiline: true),
            cuts: .prose, determinacy: .any,
            band: CompletionExpectation.band(fitting: own + lines.map(\.text)),
            forbidden: ScreenThread.labels(in: thread) + ScreenThread.snippets(in: thread), lines: lines)
    }
}
