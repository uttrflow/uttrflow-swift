// Invented clean-up cases for the speakers Docs/segments.md lists, five per segment, scored as one slice each.
import UttrflowCore

/// A kind of person whose writing a corpus slice stands for; a label beside the category, never a category.
public enum Segment: String, Sendable, Equatable, CaseIterable, Codable {
    case student
    case supportAgent = "support-agent"
    case researcher
}

extension EvaluationCorpus {
    static let segments: [EvaluationCase] = students + supportAgents + researchers

    /// A segment case, labelled so the bakeoff can report its pass rate apart from the rest.
    private static func segmentCase(
        _ segment: Segment, _ id: String, category: EvaluationCase.Category = .everyday,
        spoken: String, expected: String, keep: [String], notAdd: [String] = []
    ) -> EvaluationCase {
        .init(
            id: "segment-\(segment.rawValue)-\(id)", category: category, spoken: spoken, expected: expected,
            mustKeep: keep, mustNotAdd: notAdd, segment: segment, addedFor: 4980)
    }

    static let students: [EvaluationCase] = [
        segmentCase(
            .student, "essay-opening",
            spoken: "in this essay i will argue that the treaty of westbrook changed trade"
                + " more than it changed borders",
            expected: "In this essay I will argue that the Treaty of Westbrook changed trade"
                + " more than it changed borders.",
            keep: ["essay", "treaty", "borders"], notAdd: ["firstly"]),
        segmentCase(
            .student, "course-code",
            spoken: "the reading for bio 204 is chapter seven on cell signalling",
            expected: "The reading for BIO 204 is chapter 7 on cell signalling.",
            keep: ["204", "signalling"], notAdd: ["signaling"]),
        segmentCase(
            .student, "lab-question",
            spoken: "why did the titration overshoot when we added the base slowly",
            expected: "Why did the titration overshoot when we added the base slowly?",
            keep: ["titration", "overshoot", "base"]),
        segmentCase(
            .student, "abbreviation-ie",
            spoken: "the control group i.e. the students without tutoring scored lower",
            expected: "The control group, i.e. the students without tutoring, scored lower.",
            keep: ["i.e.", "control group", "tutoring"], notAdd: ["that is"]),
        segmentCase(
            .student, "deadline-note",
            spoken: "the draft is due on the twelfth and the final version a week later",
            expected: "The draft is due on the twelfth and the final version a week later.",
            keep: ["draft", "final version", "week"]),
    ]

    static let supportAgents: [EvaluationCase] = [
        segmentCase(
            .supportAgent, "templated-reply",
            spoken: "thanks for reaching out i have reset your password link"
                + " and it will expire in twenty four hours",
            expected: "Thanks for reaching out. I have reset your password link"
                + " and it will expire in 24 hours.",
            keep: ["reset", "password", "24"], notAdd: ["sorry"]),
        segmentCase(
            .supportAgent, "ticket-number",
            spoken: "i have escalated ticket four four one nine to the billing team",
            expected: "I have escalated ticket 4419 to the billing team.",
            keep: ["4419", "billing", "escalated"]),
        segmentCase(
            .supportAgent, "customer-name", category: .technical,
            spoken: "hi orla the refund for order seven seven two is on its way",
            expected: "Hi Orla, the refund for order 772 is on its way.",
            keep: ["Orla", "772", "refund"], notAdd: ["apologise"]),
        segmentCase(
            .supportAgent, "product-name", category: .technical,
            spoken: "please update the brightdesk app to version three point two and try again",
            expected: "Please update the Brightdesk app to version 3.2 and try again.",
            keep: ["3.2", "update", "again"]),
        segmentCase(
            .supportAgent, "short-close",
            spoken: "glad that worked let us know if anything else comes up",
            expected: "Glad that worked. Let us know if anything else comes up.",
            keep: ["worked", "anything else"], notAdd: ["please"]),
    ]

    static let researchers: [EvaluationCase] = [
        segmentCase(
            .researcher, "author-year", category: .technical,
            spoken: "as shown by Okafor et al. 2019 the effect fades after six weeks",
            expected: "As shown by Okafor et al. 2019, the effect fades after six weeks.",
            keep: ["Okafor", "et al.", "2019"], notAdd: ["and colleagues"]),
        segmentCase(
            .researcher, "sample-size", category: .technical,
            spoken: "the sample had one hundred and twenty participants and a mean age of thirty four",
            expected: "The sample had 120 participants and a mean age of 34.",
            keep: ["120", "participants", "34"]),
        segmentCase(
            .researcher, "abbreviation-eg", category: .technical,
            spoken: "several markers e.g. ferritin and albumin were measured at baseline",
            expected: "Several markers, e.g. ferritin and albumin, were measured at baseline.",
            keep: ["e.g.", "ferritin", "albumin", "baseline"], notAdd: ["for example"]),
        segmentCase(
            .researcher, "hedged-claim",
            spoken: "these results suggest but do not prove that the two pathways interact",
            expected: "These results suggest, but do not prove, that the two pathways interact.",
            keep: ["suggest", "do not prove", "pathways"]),
        segmentCase(
            .researcher, "reference-entry", category: .technical,
            spoken: "Lindqvist and Moreau 2021 journal of applied soil science volume twelve",
            expected: "Lindqvist and Moreau 2021, Journal of Applied Soil Science, volume 12.",
            keep: ["Lindqvist", "Moreau", "2021", "12"]),
    ]
}
