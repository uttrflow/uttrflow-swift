// Invented cases dictated with text after the caret, scored on the padded text the person sees.
import UttrflowCore

extension EvaluationCorpus {
    // MARK: Text after the caret. See Docs/formatting-matrix.md.

    static let followingTextCases: [EvaluationCase] =
        beforeStopCases + beforeContinuationCases + beforeClosingBracketCases + beforeParagraphCases
        + beforeOpeningBracketCases + replacingSelectionCases

    /// One case dictated into a note between `preceding` and `following`, optionally over `selected`.
    private static func caret(
        _ id: String, spoken: String, expected: String, preceding: String, following: String,
        selected: String? = nil, mustKeep: [String], mustNotAdd: [String] = [],
        mustBeginWith: String? = nil, mustEndWith: String
    ) -> EvaluationCase {
        EvaluationCase(
            id: "caret-\(id)", category: .contextual, spoken: spoken, expected: expected,
            mustKeep: mustKeep,
            context: AppContext(
                applicationName: "Notes", bundleIdentifier: "com.apple.Notes",
                documentName: "Field notes", selectedText: selected,
                precedingText: preceding, followingText: following),
            mustNotAdd: mustNotAdd, mustBeginWith: mustBeginWith, mustEndWith: mustEndWith,
            classes: [.textAfterCaret], origin: .synthetic, addedFor: 3830)
    }

    /// The stop after the caret ends the sentence, so the dictated words take none of their own.
    static let beforeStopCases: [EvaluationCase] = [
        caret(
            "before-stop-mid-sentence", spoken: "uh the ferry was delayed", expected: "the ferry was delayed",
            preceding: "On the way back ", following: ". We waited an hour.", mustKeep: ["ferry"],
            mustBeginWith: "the ferry", mustEndWith: "delayed"),
        caret(
            "before-stop-new-sentence", spoken: "the orchard needs pruning",
            expected: "The orchard needs pruning", preceding: "Spring jobs. ", following: ". Ask the warden.",
            mustKeep: ["orchard"], mustBeginWith: "The orchard", mustEndWith: "pruning"),
        caret(
            "before-question-mark", spoken: "did the parcel arrive", expected: "Did the parcel arrive",
            preceding: "", following: "? It was due today.", mustKeep: ["parcel"],
            mustBeginWith: "Did", mustEndWith: "arrive"),
        caret(
            "before-comma", spoken: "after the rain stopped", expected: "After the rain stopped",
            preceding: "", following: ", we walked to the pier.", mustKeep: ["rain"],
            mustBeginWith: "After", mustEndWith: "stopped"),
        caret(
            "before-stop-joined-word", spoken: "the lantern is cracked",
            expected: " the lantern is cracked", preceding: "We checked the shed and",
            following: ". Replace it.", mustKeep: ["lantern"], mustBeginWith: " the lantern",
            mustEndWith: "cracked"),
    ]

    /// A lowercase word after the caret continues the sentence, so no stop, and a space where it would join.
    static let beforeContinuationCases: [EvaluationCase] = [
        caret(
            "before-lowercase-spaced", spoken: "the kettle boiled", expected: "The kettle boiled",
            preceding: "", following: " and the toast burnt.", mustKeep: ["kettle"],
            mustBeginWith: "The kettle", mustEndWith: "boiled"),
        caret(
            "before-lowercase-joined", spoken: "the bridge reopened", expected: "The bridge reopened ",
            preceding: "", following: "after the storm.", mustKeep: ["bridge"],
            mustBeginWith: "The bridge", mustEndWith: "reopened "),
        caret(
            "before-lowercase-mid-sentence", spoken: "two spare tyres", expected: "two spare tyres ",
            preceding: "We packed ", following: "and a pump.", mustKeep: ["tyres"],
            mustBeginWith: "two spare", mustEndWith: "tyres "),
        caret(
            "before-lowercase-both-joined", spoken: "the blue", expected: " the blue ",
            preceding: "Paint", following: "fence first.", mustKeep: ["blue"],
            mustBeginWith: " the blue", mustEndWith: "blue "),
        caret(
            "before-lowercase-after-question-word", spoken: "uh when the shop opens",
            expected: "when the shop opens", preceding: "Ask the baker ", following: " so we can buy bread.",
            mustKeep: ["shop"], mustBeginWith: "when the", mustEndWith: "opens"),
    ]

    /// A bracket the caret sits inside closes after it, so the words take no stop and no trailing space.
    static let beforeClosingBracketCases: [EvaluationCase] = [
        caret(
            "inside-parentheses", spoken: "about forty minutes", expected: "about 40 minutes",
            preceding: "The walk is short (", following: ") and flat.", mustKeep: ["minutes"],
            mustBeginWith: "about", mustEndWith: "minutes"),
        caret(
            "inside-square-brackets", spoken: "uh see the map", expected: "see the map",
            preceding: "Turn left at the mill [", following: "] and keep going.", mustKeep: ["map"],
            mustBeginWith: "see", mustEndWith: "map"),
        caret(
            "inside-parentheses-end-of-sentence", spoken: "uh weather permitting",
            expected: "weather permitting", preceding: "We sail on Saturday (", following: ").",
            mustKeep: ["permitting"], mustBeginWith: "weather", mustEndWith: "permitting"),
        caret(
            "inside-parentheses-after-space", spoken: "uh the old one", expected: "the old one",
            preceding: "Bring the ladder ( ", following: " ) to the barn.", mustKeep: ["old"],
            mustBeginWith: "the old", mustEndWith: "one"),
        caret(
            "inside-curly-quotes", spoken: "uh back by noon", expected: "back by noon",
            preceding: "The sign said \u{201C}", following: "\u{201D} on the door.", mustKeep: ["noon"],
            mustBeginWith: "back", mustEndWith: "noon"),
    ]

    /// A new paragraph after the caret ends the sentence here, so the words take their stop.
    static let beforeParagraphCases: [EvaluationCase] = [
        caret(
            "before-paragraph", spoken: "the hens laid six eggs", expected: "The hens laid six eggs.",
            preceding: "", following: "\n\nTomorrow we clean the coop.", mustKeep: ["hens"],
            mustBeginWith: "The hens", mustEndWith: "eggs."),
        caret(
            "before-line-break", spoken: "the gate is fixed", expected: "The gate is fixed.",
            preceding: "Done today\n", following: "\nStill to do", mustKeep: ["gate"],
            mustBeginWith: "The gate", mustEndWith: "fixed."),
        caret(
            "before-paragraph-mid-note", spoken: "we ran out of nails",
            expected: "We ran out of nails.", preceding: "The roof is half done. ",
            following: "\n\nOrder more on Monday.", mustKeep: ["nails"], mustBeginWith: "We ran",
            mustEndWith: "nails."),
        caret(
            "before-paragraph-lowercase", spoken: "the pump needs a new washer",
            expected: "The pump needs a new washer.", preceding: "",
            following: "\n\nand the hose is split.", mustKeep: ["washer"], mustBeginWith: "The pump",
            mustEndWith: "washer."),
        caret(
            "before-paragraph-asks", spoken: "can you bring the trailer",
            expected: "Can you bring the trailer?", preceding: "", following: "\n\nThanks.",
            mustKeep: ["trailer"], mustBeginWith: "Can you", mustEndWith: "trailer?"),
    ]

    /// An aside in brackets after the caret belongs to the dictated sentence, so the stop waits for it.
    static let beforeOpeningBracketCases: [EvaluationCase] = [
        caret(
            "before-parenthetical", spoken: "the market opens at eight",
            expected: "The market opens at eight", preceding: "", following: " (on weekdays).",
            mustKeep: ["market"], mustNotAdd: ["eight."], mustBeginWith: "The market", mustEndWith: "at eight"
        ),
        caret(
            "before-parenthetical-joined", spoken: "the cottage has two rooms",
            expected: "The cottage has two rooms ", preceding: "", following: "(and a loft).",
            mustKeep: ["cottage"], mustNotAdd: ["rooms."], mustBeginWith: "The cottage",
            mustEndWith: "rooms "),
        caret(
            "before-bracket-note", spoken: "we leave at dawn", expected: "We leave at dawn",
            preceding: "", following: " [weather allowing].", mustKeep: ["dawn"], mustNotAdd: ["dawn."],
            mustBeginWith: "We leave", mustEndWith: "dawn"),
        caret(
            "before-parenthetical-mid-sentence", spoken: "uh the long trail", expected: "the long trail",
            preceding: "We took ", following: " (twelve miles) back to camp.", mustKeep: ["trail"],
            mustNotAdd: ["trail."], mustBeginWith: "the long", mustEndWith: "trail"),
        caret(
            "before-open-quote", spoken: "the label reads", expected: "The label reads",
            preceding: "", following: " \u{201C}keep dry\u{201D}.", mustKeep: ["label"],
            mustNotAdd: ["reads."], mustBeginWith: "The label", mustEndWith: "reads"),
    ]

    /// A selection is replaced: the text after it, not the selection, decides the stop and the spacing.
    static let replacingSelectionCases: [EvaluationCase] = [
        caret(
            "replace-mid-sentence", spoken: "on thursday", expected: "on Thursday",
            preceding: "The fair is ", following: " this year.", selected: "on friday",
            mustKeep: ["Thursday"], mustBeginWith: "on", mustEndWith: "Thursday"),
        caret(
            "replace-before-stop", spoken: "uh the north field", expected: "the north field",
            preceding: "Plough ", following: ".", selected: "the south field", mustKeep: ["north"],
            mustBeginWith: "the north", mustEndWith: "field"),
        caret(
            "replace-whole-sentence", spoken: "the van is booked", expected: "The van is booked.",
            preceding: "Moving day. ", following: "\n\nPack the books.", selected: "Book the van.",
            mustKeep: ["van"], mustBeginWith: "The van", mustEndWith: "booked."),
        caret(
            "replace-joined-word", spoken: "green", expected: " green ",
            preceding: "The", following: "door is stiff.", selected: "red", mustKeep: ["green"],
            mustBeginWith: " green", mustEndWith: "green "),
        caret(
            "replace-before-lowercase", spoken: "the dog is fed", expected: "The dog is fed",
            preceding: "", following: " and the cat is out.", selected: "Feed the dog.",
            mustKeep: ["dog"], mustBeginWith: "The dog", mustEndWith: "fed"),
    ]
}
