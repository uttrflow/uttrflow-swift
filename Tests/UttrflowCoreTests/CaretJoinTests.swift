import Testing

@testable import UttrflowCore

@Suite("CaretJoin")
struct CaretJoinTests {
    /// One caret edge: the text before it, the dictated words, the text after it, where, and what is written.
    struct Edge: Sendable, CustomTestStringConvertible {
        let preceding: String
        let dictated: String
        let following: String
        let destination: Destination
        let written: String

        var testDescription: String { "\(preceding)|\(dictated)|\(following) in \(destination)" }
    }

    static let trailingEdges: [Edge] = [
        Edge(preceding: "", dictated: "okay", following: "world", destination: .plain, written: "okay "),
        Edge(
            preceding: "", dictated: "okay", following: "(see below)", destination: .plain, written: "okay "),
        Edge(preceding: "", dictated: "okay", following: "[1]", destination: .document, written: "okay "),
        Edge(preceding: "", dictated: "okay", following: "{x}", destination: .email, written: "okay "),
        Edge(
            preceding: "", dictated: "okay", following: "\u{201C}hi\u{201D}", destination: .plain,
            written: "okay "),
        Edge(preceding: "", dictated: "okay", following: "$5", destination: .plain, written: "okay "),
        Edge(preceding: "", dictated: "okay", following: "@sam", destination: .messaging, written: "okay "),
        Edge(
            preceding: "", dictated: "okay", following: "#launch", destination: .messaging, written: "okay "),
        Edge(preceding: "", dictated: "okay", following: "\u{20B9}40", destination: .plain, written: "okay "),
        Edge(
            preceding: "", dictated: "okay", following: "\u{1F600}", destination: .messaging, written: "okay "
        ),
        Edge(preceding: "", dictated: "okay", following: ".", destination: .plain, written: "okay"),
        Edge(preceding: "", dictated: "okay", following: ", then", destination: .plain, written: "okay"),
        Edge(preceding: "", dictated: "okay", following: ")", destination: .plain, written: "okay"),
        Edge(preceding: "", dictated: "okay", following: "\u{201D}", destination: .plain, written: "okay"),
        Edge(preceding: "", dictated: "okay", following: "\"", destination: .plain, written: "okay"),
        Edge(preceding: "", dictated: "okay", following: " world", destination: .plain, written: "okay"),
        Edge(preceding: "", dictated: "okay", following: "\nworld", destination: .plain, written: "okay"),
        Edge(preceding: "", dictated: "okay,", following: "world", destination: .plain, written: "okay, "),
        Edge(preceding: "", dictated: "said (", following: "world", destination: .plain, written: "said ("),
        Edge(preceding: "", dictated: "cost $", following: "5", destination: .plain, written: "cost $"),
        Edge(
            preceding: "", dictated: "I write C#", following: "daily", destination: .plain,
            written: "I write C# "),
        Edge(
            preceding: "", dictated: "print", following: "(value)", destination: .codeEditor, written: "print"
        ),
        Edge(preceding: "", dictated: "items", following: "[0]", destination: .codeEditor, written: "items"),
        Edge(preceding: "", dictated: "echo", following: "(x)", destination: .terminal, written: "echo"),
        Edge(preceding: "", dictated: "count", following: "(*)", destination: .sqlEditor, written: "count"),
        Edge(preceding: "", dictated: "echo", following: "$HOME", destination: .terminal, written: "echo "),
        Edge(preceding: "", dictated: "x", following: "= 1", destination: .codeEditor, written: "x "),
        Edge(
            preceding: "", dictated: "value", following: "world", destination: .codeEditor, written: "value "),
    ]

    static let leadingEdges: [Edge] = [
        Edge(preceding: "the", dictated: "store", following: "", destination: .plain, written: " store"),
        Edge(preceding: "Hello,", dictated: "world", following: "", destination: .plain, written: " world"),
        Edge(preceding: "end.", dictated: "Next", following: "", destination: .plain, written: " Next"),
        Edge(preceding: "50%", dictated: "off", following: "", destination: .plain, written: " off"),
        Edge(preceding: "(see", dictated: "below)", following: "", destination: .plain, written: " below)"),
        Edge(preceding: "said)", dictated: "then", following: "", destination: .plain, written: " then"),
        Edge(
            preceding: "\u{1F600}", dictated: "great", following: "", destination: .messaging,
            written: " great"),
        Edge(preceding: "(", dictated: "see", following: "", destination: .plain, written: "see"),
        Edge(preceding: "\u{201C}", dictated: "hi", following: "", destination: .plain, written: "hi"),
        Edge(preceding: "$", dictated: "5", following: "", destination: .plain, written: "5"),
        Edge(preceding: "@", dictated: "sam", following: "", destination: .messaging, written: "sam"),
        Edge(preceding: "#", dictated: "launch", following: "", destination: .messaging, written: "launch"),
        Edge(preceding: "ping @", dictated: "sam", following: "", destination: .messaging, written: "sam"),
        Edge(
            preceding: "tag #", dictated: "launch", following: "", destination: .messaging, written: "launch"),
        Edge(preceding: "cost $", dictated: "42", following: "", destination: .plain, written: "42"),
        Edge(
            preceding: "mail sam@", dictated: "example.com", following: "", destination: .email,
            written: "example.com"),
        Edge(
            preceding: "I write C#", dictated: "daily", following: "", destination: .plain, written: " daily"),
        Edge(preceding: "Hello ", dictated: "world", following: "", destination: .plain, written: "world"),
        Edge(preceding: "line\n", dictated: "world", following: "", destination: .plain, written: "world"),
        Edge(preceding: "fifty", dictated: "%", following: "", destination: .plain, written: "%"),
        Edge(
            preceding: "word", dictated: "(see below)", following: "", destination: .plain,
            written: " (see below)"),
        Edge(preceding: "word", dictated: "$5", following: "", destination: .plain, written: " $5"),
        Edge(
            preceding: "word", dictated: "\u{201C}hi\u{201D}", following: "", destination: .plain,
            written: " \u{201C}hi\u{201D}"),
        Edge(
            preceding: "print", dictated: "(value)", following: "", destination: .codeEditor,
            written: "(value)"),
        Edge(preceding: "items", dictated: "[0]", following: "", destination: .codeEditor, written: "[0]"),
        Edge(
            preceding: "let x =", dictated: "value", following: "", destination: .codeEditor,
            written: " value"),
        Edge(preceding: "well -", dictated: "yes", following: "", destination: .plain, written: " yes"),
        Edge(preceding: "git", dictated: "status", following: "", destination: .terminal, written: " status"),
    ]

    @Test(
        "the trailing edge is decided by the classes either side and the destination",
        arguments: trailingEdges)
    func trailingEdge(edge: Edge) {
        let point = InsertionPoint(precedingText: edge.preceding, followingText: edge.following)
        #expect(point.paddedBoundary(for: edge.dictated, in: edge.destination) == edge.written)
    }

    @Test("the leading edge is decided by the same table", arguments: leadingEdges)
    func leadingEdge(edge: Edge) {
        let point = InsertionPoint(precedingText: edge.preceding, followingText: nil)
        #expect(point.paddedBoundary(for: edge.dictated, in: edge.destination) == edge.written)
    }

    @Test("every class pair outside code is the same in every prose destination")
    func proseDestinationsAgree() {
        let prose = Destination.allCases.filter { !CaretJoin.codeDestinations.contains($0) }
        for before in CaretJoin.CharacterClass.allCases {
            for after in CaretJoin.CharacterClass.allCases {
                let answers = Set(prose.map { CaretJoin.needsSpace(between: before, and: after, in: $0) })
                #expect(answers.count == 1)
            }
        }
    }
}
