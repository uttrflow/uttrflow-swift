import Testing
import UttrflowTestSupport

@testable import UttrflowCore
@testable import UttrflowPipeline

/// Whatever pieces and pauses are joined, no destination gets structure the speaker did not give it.
@Suite("Structure invariants")
struct StructureInvariantTests {
    private static let sentences = [
        "We shipped the sync fix.", "The retry service now backs off.", "Billing is next.",
        "First, finish onboarding.", "Second, fix login.", "Then we review the design and",
        "the numbers are 12", "50 dollars in total.", "Call me at the office,", "see (the notes",
        "attached) before Monday.", "Thanks.",
    ]
    private static let destinations: [Destination] = [
        .document, .email, .messaging, .plain, .spreadsheet, .codeEditor,
    ]

    private func laid(_ pieces: [String], pauses: [Double], _ destination: Destination) -> String {
        PieceJoiner.laidOut(
            pieces, under: .standard(for: destination), pauses: pauses.map { .seconds($0) })
    }

    /// The paragraph breaks of a text that stand where one cannot: after a word that leads on or a comma, inside a bracket.
    static func misplacedBreaks(in text: String) -> [String] {
        var found: [String] = []
        let parts = text.components(separatedBy: "\n\n")
        for (number, part) in parts.dropLast().enumerated() {
            let words = part.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let last = words.last else { continue }
            if last.hasSuffix(",") || last.hasSuffix(";") { found.append("comma before break \(number)") }
            if MarkLegality.state(of: last) == .leadsOn { found.append("leads on before break \(number)") }
            let opens = part.filter { "([{".contains($0) }.count
            let closes = part.filter { ")]}".contains($0) }.count
            if opens > closes { found.append("open bracket before break \(number)") }
        }
        return found
    }

    @Test(
        "no destination breaks a line inside a sentence, a bracket or a number",
        arguments: Seeded.seeds(0..<200))
    func neverInvented(seed: Int) {
        var random = Seeded(seed: seed)
        let count = Int.random(in: 1...6, using: &random)
        let pieces = (0..<count).map { _ in random.pick(Self.sentences) }
        let pauses = (0..<count).map { _ in random.pick([0, 0.3, 1.0, 1.6, 2.5, 4.0]) }
        for destination in Self.destinations {
            let text = laid(pieces, pauses: pauses, destination)
            #expect(
                Self.misplacedBreaks(in: text).isEmpty, "\(random) \(destination): \(text.debugDescription)")
        }
    }

    /// One-topic speech with pauses in it: the pieces are cut where the speaker breathed, and nothing is a new subject.
    private static let oneTopic: [(pieces: [String], pauses: [Double])] = [
        (["We shipped the sync fix and", "the retry service now backs off."], [0, 3.0]),
        (["I looked at the build", "and the logs show a timeout in the upload step."], [0, 2.8]),
        (["The new screen has a title", "a short description and a button."], [0, 2.2]),
        (["We should move the release to Friday because", "the tests are still running."], [0, 4.0]),
        (["Please send me the report,", "the one from last week."], [0, 2.6]),
        (["The meeting is at three.", "It runs for about an hour."], [0, 1.0]),
        (["He opened the door", "and walked into the room.", "Nobody was there."], [0, 1.3, 1.2]),
        (["The invoice total is twelve", "dollars and fifty cents."], [0, 2.4]),
    ]

    @Test("one-topic speech with pauses ends with no break", arguments: StructureInvariantTests.destinations)
    func noInventedStructure(destination: Destination) {
        for speech in Self.oneTopic {
            let text = laid(speech.pieces, pauses: speech.pauses, destination)
            #expect(!text.contains("\n"), "\(destination): \(speech.pieces) -> \(text.debugDescription)")
        }
    }
}
