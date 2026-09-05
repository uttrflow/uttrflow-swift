import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAI

/// Transcripts that look like they contain a trigger and do not; the passing score is zero expansions.
@Suite("Words that look like triggers and are not")
struct SnippetNearMissTests {
    /// A deliberately dangerous set: short triggers, and words common enough to appear inside other words.
    private static let snippets: [Snippet] = [
        makeSnippet(trigger: "pr", expansion: "pull request"),
        makeSnippet(trigger: "add", expansion: "Adobe Acrobat"),
        makeSnippet(trigger: "my address", expansion: "Flat 402, Sample Road, Bengaluru 560001"),
        makeSnippet(trigger: "sign off", expansion: "Thanks, Naveen"),
        makeSnippet(trigger: "stand up", expansion: "Yesterday: … Today: … Blockers: …"),
        makeSnippet(trigger: "meeting link", expansion: "https://meet.google.com/qzt-hnrv-dka"),
    ]

    /// Each a different way of being close: inside a word, glued, across a sentence end, or quoted.
    static let nearMisses: [String] = [
        // A trigger inside a longer word. Nothing here is a word run of its own.
        "Please approve the change before Friday.",
        "The appraisal came back higher than expected.",
        "Her address book is out of date.",
        "The standup is at ten past nine.",
        "The meeting linkage between the two teams was unclear.",
        "He was signing off as I walked in.",

        // A trigger glued to a neighbour by punctuation, which makes one written word of two runs.
        "The PR-review queue is empty.",
        "The add-on costs extra.",
        // Glued on the left rather than the right. Both ends have to be checked.
        "We will re-add the item tomorrow.",
        "Send round the pre-meeting link agenda.",
        "Write to pr@example.com instead.",
        "Check the sign_off script in the repo.",
        "Please review the sign-off sheet.",
        "My address's postcode changed last year.",
        "The pr/fr split is not worth arguing about.",

        // A trigger assembled from two thoughts; punctuation tolerance stops at a sentence end.
        "Please sign. Off we go.",
        "Everyone please stand; up to you whether you speak.",
        "That is my. Address unknown.",

        // A trigger whose words are all present, in a longer phrase that is not it.
        "Send it to my home address.",
        "I gave them my old address by mistake.",

        // The user quoting the expansion back. Saying it is not asking for it again.
        "Sign off with Thanks, Naveen at the bottom.",
        "The link is https://meet.google.com/qzt-hnrv-dka — that is the meeting link.",
    ]

    @Test("expands nothing it should not", arguments: nearMisses)
    func nothingExpands(transcript: String) {
        let result = SnippetExpander(snippets: Self.snippets).expand(transcript)
        #expect(!result.didExpand, "expanded: \(result.applied.map(\.matched))")
        #expect(result.text == transcript)
    }

    /// The same snippets said properly, so a matcher that never fires cannot pass by silence.
    @Test(
        "and still expands the real thing",
        arguments: [
            "Raise a pr for it.",
            "Please add that to the list.",
            "My address.",
            "I will sign off now.",
            "Time for the stand up.",
            "Here is the meeting link.",
        ]
    )
    func theRealThingStillWorks(transcript: String) {
        #expect(SnippetExpander(snippets: Self.snippets).expand(transcript).didExpand)
    }

    @Test("at least ten ways of being nearly right are checked")
    func theSetIsBigEnough() {
        #expect(Self.nearMisses.count >= 10)
    }
}
