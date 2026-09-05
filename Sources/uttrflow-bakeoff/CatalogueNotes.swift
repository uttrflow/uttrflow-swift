import UttrflowPredict

extension FixtureCatalogue {
    /// Prose after earlier paragraphs in a note and a document, and the short entries of two lists.
    static let notes: [Scenario] = [
        Scenario(
            category: "notes", name: "release",
            situation: GenerationSituation(
                application: "Notes", field: "Note Body Text View",
                preceding: """
                    The release goes out on Thursday. We measured latency on the larger model and it held \
                    under a second at the 95th percentile. The download page still shows last month's build.
                    """,
                windowTitle: "Release notes",
                recentLines: [
                    "The download page still shows last month's build.",
                    "We measured latency on the larger model and it held under a second at the 95th percentile.",
                    "The release goes out on Thursday.", "Nobody reads the second paragraph.",
                ],
                isMultiline: true),
            cuts: .prose, determinacy: .any, band: 1...120,
            forbidden: [
                "release goes out on Thursday", "measured latency on the larger", "shows last month's build",
            ],
            lines: [
                "The next release adds tab-to-complete in every text field.",
                "We should measure the smaller model before shipping it.",
                "Latency on the smaller model is still unmeasured.",
                "Nobody reads the second paragraph, so keep it short.",
                "Open questions for Thursday:", "The download page needs the new build number.",
                "Sam will write the announcement.", "Remember to tag the release before the demo.",
                "The beta group found two bugs in the address bar.",
                "Next week we start on speculative decoding.",
            ]),
        Scenario(
            category: "notes", name: "report",
            situation: GenerationSituation(
                application: "Pages", field: "Body", document: "Quarterly review.pages",
                preceding: """
                    Brightleaf's second quarter closed with three releases and a steady rise in daily active use. \
                    The team stayed at six people, and the pilot with two Bengaluru schools ran to plan.

                    Most of the quarter's engineering time went into the local model: the first suggestion now \
                    appears well under a second on the machines our customers own.
                    """,
                windowTitle: "Quarterly review",
                recentLines: [
                    "Most of the quarter's engineering time went into the local model.",
                    "The team stayed at six people, and the pilot with two Bengaluru schools ran to plan.",
                    "Brightleaf's second quarter closed with three releases.",
                ],
                isMultiline: true),
            cuts: .prose, determinacy: .any, band: 1...140,
            forbidden: ["closed with three releases", "stayed at six people", "went into the local model"],
            lines: [
                "In the third quarter the team plans to ship the public beta.",
                "The most requested feature was a faster first suggestion.",
                "Support tickets fell by a third after the update.",
                "We plan to hire two engineers in the autumn.",
                "The main risk remains the cost of the larger model.",
                "Customers in India now make up half of new sign-ups.",
                "Revenue grew modestly while churn stayed flat.",
                "Our next milestone is the public beta in October.",
                "This report was prepared for the board meeting.",
                "Feedback from the pilot was mostly positive.",
            ]),
        Scenario(
            category: "notes", name: "groceries",
            situation: GenerationSituation(
                application: "Notes", field: "Note Body Text View", preceding: "milk\neggs\nbread",
                windowTitle: "Groceries", recentLines: ["bread", "eggs", "milk", "coffee", "apples"],
                isMultiline: true),
            cuts: [.characters(2), .midWord(1)], determinacy: .word, band: 1...20,
            known: ["tea", "toast", "rice", "onions", "butter"],
            lines: [
                "butter", "coffee", "bananas", "tomatoes", "onions", "yoghurt", "toothpaste", "dish soap",
                "chicken",
                "spinach", "olive oil", "paneer",
            ]),
        Scenario(
            category: "notes", name: "todo",
            situation: GenerationSituation(
                application: "Notes", field: "Note Body Text View",
                preceding: "- call the bank\n- renew passport",
                windowTitle: "This week",
                recentLines: ["- renew passport", "- call the bank", "- book flights"],
                isMultiline: true),
            cuts: [.midWord(2), .afterWord(2), .midWord(3)], determinacy: .any, band: 1...40,
            forbidden: ["call the bank", "renew passport"],
            lines: [
                "- book dentist appointment", "- pay electricity bill", "- return library books",
                "- fix the kitchen tap", "- send invoice to Sam", "- buy birthday gift for Priya",
                "- water the plants", "- cancel gym membership",
            ]),
    ]
}
