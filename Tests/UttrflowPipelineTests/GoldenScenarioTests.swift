import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

/// One row of `Docs/golden-scenarios.md`: a dictation said as a person says it and the text it must write.
struct GoldenRow: Sendable, CustomTestStringConvertible {
    let id: String
    let behaviour: String
    /// The open issue whose fix makes the row pass; the row is expected to fail until then.
    let knownIssue: String?
    /// Runs the row and names what differed from the requirement, or nil when it holds.
    let check: @Sendable () async -> String?

    var testDescription: String { "\(id) \(behaviour)" }

    /// A row that runs one scripted dictation and compares everything the field was handed with `expected`.
    init(
        _ id: String, _ behaviour: String, knownIssue: String? = nil, _ scenario: Scenario,
        writes expected: String
    ) {
        self.init(id, behaviour, knownIssue: knownIssue) {
            let written = await ScenarioDriver.run(scenario).writes.joined()
            return written == expected
                ? nil : "wrote \(written.debugDescription), wanted \(expected.debugDescription)"
        }
    }

    init(
        _ id: String, _ behaviour: String, knownIssue: String? = nil,
        check: @escaping @Sendable () async -> String?
    ) {
        self.id = id
        self.behaviour = behaviour
        self.knownIssue = knownIssue
        self.check = check
    }
}

/// The rows of `Docs/golden-scenarios.md` that run in `make verify`, and the ones that wait for the gate or the bench.
enum GoldenScenarios {
    static let sqlClient = AppContext(
        applicationName: "TablePlus", bundleIdentifier: DestinationRules.tablePlus)
    static let notes = AppContext(applicationName: "Notes", bundleIdentifier: DestinationRules.notes)
    static let chat = AppContext(applicationName: "Slack", bundleIdentifier: DestinationRules.slack)
    static let terminal = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")

    /// Rows that need the transcription gate, the bench, the profile store or the source tree, not the scripted driver.
    static let deferred: [String: String] = [
        "G1.7": "a hedged sentence waits for the hedge decision",
        "G6.1": "the profile store is not wired into the scripted driver",
        "G6.2": "the profile store is not wired into the scripted driver",
        "G6.3": "the profile store is not wired into the scripted driver",
        "G6.4": "the profile store is not wired into the scripted driver",
        "G7.1": "bench: key-up to insertion on the reference Mac",
        "G7.2": "gate and bench: the real recogniser on synthesised clips",
        "G7.3": "bench: first dictation after launch",
        "G7.4": "the rules-first switch is not a setting the driver can flip",
        "G8.1": "held-out variants need their own fixture set",
        "G8.2": "the model path answers from a scripted model per sentence",
        "G8.3": "source-tree audit, run by the closed-list audit",
    ]

    static func scenario(
        _ context: AppContext, _ pieces: [ScriptedPiece]
    ) -> Scenario {
        Scenario(pieces: pieces, context: context)
    }

    static func said(_ context: AppContext, _ text: String) -> Scenario {
        scenario(context, [ScriptedPiece(text)])
    }

    static func prose(_ before: String? = nil) -> AppContext {
        AppContext(
            applicationName: "Notes", bundleIdentifier: DestinationRules.notes, precedingText: before)
    }

    static func sql(before: String? = nil) -> AppContext {
        AppContext(
            applicationName: "TablePlus", bundleIdentifier: DestinationRules.tablePlus,
            precedingText: before)
    }

    static let rows: [GoldenRow] = sqlRows + gitRows + punctuationRows + paragraphRows + numberRows

    static let sqlRows: [GoldenRow] = [
        GoldenRow(
            "G1.1", "a minute of SQL speech in a database client is the formatted statement said",
            knownIssue: "#4212",
            scenario(
                sql(),
                [
                    ScriptedPiece("Select everything from orders."),
                    ScriptedPiece("Join customers on orders dot customer ID", pauseBefore: 1.1),
                    ScriptedPiece("equals customers dot ID.", pauseBefore: 0.9),
                    ScriptedPiece(
                        "Where created at is after the first of January 2026.", pauseBefore: 1.4),
                ]),
            writes:
                "SELECT *\nFROM orders\nJOIN customers ON orders.customer_id = customers.id\nWHERE created_at > '2026-01-01'"
        ),
        GoldenRow(
            "G1.2", "SQL speech with the editor unreadable keeps keywords and invents no identifier",
            knownIssue: "#4212",
            scenario(
                AppContext(
                    applicationName: "TablePlus", bundleIdentifier: DestinationRules.tablePlus,
                    unavailable: .refused),
                [
                    ScriptedPiece("Select everything from orders."),
                    ScriptedPiece("Join customers on orders dot customer ID", pauseBefore: 1.1),
                    ScriptedPiece("equals customers dot ID.", pauseBefore: 0.9),
                ]),
            writes: "SELECT *\nFROM orders\nJOIN customers ON orders.customer_id = customers.id"),
        GoldenRow(
            "G1.3", "a clause said mid-statement continues it in upper-case keywords without a stop",
            knownIssue: "#4212",
            said(
                sql(before: "SELECT *\nFROM orders\n"),
                "Where status equals quote paid quote and total greater than 12,000."),
            writes: "WHERE status = 'paid' AND total > 12000"),
        GoldenRow(
            "G1.4", "prose said after a comment marker in an editor stays prose", knownIssue: "#3888",
            said(
                sql(before: "-- "), "The nightly backup finished before the migration started."),
            writes: "The nightly backup finished before the migration started."),
        GoldenRow("G1.5", "the same prose is written under every persona", check: Self.personaProse),
        GoldenRow(
            "G1.6", "a statement cut at a pause is the statement said in one piece", knownIssue: "#4212",
            scenario(
                sql(),
                [
                    ScriptedPiece("Select ID from orders where status equals quote paid quote."),
                    ScriptedPiece("And total greater than 12,000.", pauseBefore: 1.2),
                ]),
            writes: "SELECT id\nFROM orders\nWHERE status = 'paid' AND total > 12000"),
    ]

    static let gitRows: [GoldenRow] = [
        GoldenRow(
            "G2.1", "a command word heard wrong is corrected by the sentence before it", knownIssue: "#3599",
            scenario(
                prose("I just committed the retry fix. "),
                [ScriptedPiece("Now I need to gate push it before the demo.", wordConfidence: 0.31)]),
            writes: "Now I need to git push it before the demo."),
        GoldenRow(
            "G2.2", "a command word heard wrong in a terminal is written as spoken", knownIssue: "#3591",
            said(terminal, "Get push origin main."), writes: "git push origin main"),
        GoldenRow(
            "G2.3", "a sentence about a gate push is never overridden",
            said(prose(), "The gate push was blocked by the lock."),
            writes: "The gate push was blocked by the lock."),
        GoldenRow(
            "G2.4", "the first sentence alone corrects the second", knownIssue: "#3599",
            scenario(
                prose("I am about to commit this change. "),
                [ScriptedPiece("Then get push.", wordConfidence: 0.4)]),
            writes: "Then git push."),
        GoldenRow(
            "G2.5", "a short clip in a terminal is the command said", knownIssue: "#4241",
            said(terminal, "Get push."), writes: "git push"),
    ]

    static let punctuationRows: [GoldenRow] = [
        GoldenRow(
            "G3.1", "no stop stands where a piece is cut in the middle of a clause", knownIssue: "#3605",
            scenario(
                notes,
                [
                    ScriptedPiece("We should ship the build on Friday and then."),
                    ScriptedPiece("Tell the team.", pauseBefore: 0.9),
                ]),
            writes: "We should ship the build on Friday and then tell the team."),
        GoldenRow(
            "G3.2", "a comma at a piece's end is kept once",
            scenario(
                notes,
                [
                    ScriptedPiece("I called the vendor,"),
                    ScriptedPiece("and they said no.", pauseBefore: 0.9),
                ]),
            writes: "I called the vendor, and they said no."),
        GoldenRow(
            "G3.3", "a dictation released mid-clause gets no stop", knownIssue: "#3605",
            said(notes, "We should ship the build on Friday and then"),
            writes: "We should ship the build on Friday and then"),
        GoldenRow(
            "G3.4", "an amount cut inside its number is written whole", knownIssue: "#4027",
            scenario(
                notes,
                [
                    ScriptedPiece("The invoice total is two thousand"),
                    ScriptedPiece("five hundred dollars.", pauseBefore: 0.9),
                ]),
            writes: "The invoice total is $2,500."),
        GoldenRow("G3.5", "no cut position leaves a doubled or stranded mark", check: Self.cutProperty),
    ]

    static let paragraphRows: [GoldenRow] = [
        GoldenRow(
            "G4.1", "points separated by long pauses are separate paragraphs",
            scenario(
                notes,
                [
                    ScriptedPiece("The backend migration is finished."),
                    ScriptedPiece("The old tables are now read only.", pauseBefore: 0.5),
                    ScriptedPiece("The new layout follows the design review.", pauseBefore: 2.6),
                    ScriptedPiece("Spacing is tighter on small screens.", pauseBefore: 0.5),
                    ScriptedPiece("The release is planned for next week.", pauseBefore: 2.4),
                    ScriptedPiece("Notes for it are drafted.", pauseBefore: 0.5),
                ]),
            writes:
                "The backend migration is finished. The old tables are now read only.\n\nThe new layout follows the design review. Spacing is tighter on small screens.\n\nThe release is planned for next week. Notes for it are drafted."
        ),
        GoldenRow(
            "G4.2", "points in a chat composer arrive in one insertion", knownIssue: "#3759",
            scenario(
                chat,
                [
                    ScriptedPiece("The backend migration is finished."),
                    ScriptedPiece("The new layout follows the design review.", pauseBefore: 2.6),
                    ScriptedPiece("The release is planned for next week.", pauseBefore: 2.4),
                ]),
            writes:
                "The backend migration is finished.\nThe new layout follows the design review.\nThe release is planned for next week."
        ),
        GoldenRow(
            "G4.3", "spoken ordinals become a numbered list", knownIssue: "#3629",
            said(notes, "First fix the login bug second speed up the export third update the docs"),
            writes: "1. Fix the login bug\n2. Speed up the export\n3. Update the docs"),
        GoldenRow(
            "G4.4", "sentences one second apart stay one paragraph",
            scenario(
                notes,
                [
                    ScriptedPiece("The export is faster now."),
                    ScriptedPiece("It writes in the background.", pauseBefore: 1.0),
                    ScriptedPiece("It reports progress as it goes.", pauseBefore: 1.0),
                    ScriptedPiece("Cancelling it leaves no partial file.", pauseBefore: 1.0),
                    ScriptedPiece("Large files no longer stall the window.", pauseBefore: 1.0),
                ]),
            writes:
                "The export is faster now. It writes in the background. It reports progress as it goes. Cancelling it leaves no partial file. Large files no longer stall the window."
        ),
    ]

    static let numberRows: [GoldenRow] = [
        GoldenRow(
            "G5.1", "spoken numbers and currency become numerals and currency", knownIssue: "#4027",
            said(notes, "i paid five dollars for three apples and twelve oranges"),
            writes: "I paid $5 for 3 apples and 12 oranges."),
        GoldenRow(
            "G5.2", "large amounts and percentages are written as figures", knownIssue: "#4027",
            said(
                notes,
                "the budget is two hundred fifty thousand dollars and the fee is two point five percent"),
            writes: "The budget is $250,000 and the fee is 2.5%."),
        GoldenRow(
            "G5.3", "a time and a pounds amount are written as figures", knownIssue: "#4049",
            said(chat, "meet at six thirty and it costs three pounds fifty"),
            writes: "Meet at 6:30 and it costs £3.50"),
        GoldenRow(
            "G5.4", "a comparison in SQL is a bare symbol and number", knownIssue: "#4212",
            said(sql(before: "SELECT * FROM orders\n"), "where total is greater than twelve thousand"),
            writes: "WHERE total > 12000"),
        GoldenRow(
            "G5.5", "idioms with numbers in them stay words",
            said(notes, "no one came and one of the best was my two cents"),
            writes: "No one came and one of the best was my two cents."),
    ]

    static func personaProse() async -> String? {
        let said = "The nightly backup finished before the migration started."
        var profiles: [UserProfile] = [.default]
        profiles.append(UserProfile(preferredLanguages: [.english], pauses: .long))
        profiles.append(UserProfile(preferredLanguages: [.english], pauses: .veryLong))
        for profile in profiles {
            var scenario = Self.said(prose(), said)
            scenario.profile = profile
            let written = await ScenarioDriver.run(scenario).writes.joined()
            if written != said { return "wrote \(written.debugDescription) under \(profile)" }
        }
        return nil
    }

    static let cutSentences = [
        "We should ship the build on Friday and then tell the team about the plan.",
        "I called the vendor, and they said no, so we looked elsewhere.",
        "The invoice total is two thousand five hundred dollars for the month.",
        "Remember the following list: milk, eggs and bread for the weekend.",
        "She asked whether the meeting moved, and I said it did not.",
    ]

    static func cutProperty() async -> String? {
        let bad = [",.", ".,", "..", " ,"]
        for sentence in cutSentences {
            let words = sentence.split(separator: " ").map(String.init)
            for cut in 1..<words.count {
                let pieces = [
                    ScriptedPiece(words[..<cut].joined(separator: " ") + "."),
                    ScriptedPiece(words[cut...].joined(separator: " "), pauseBefore: 0.9),
                ]
                let written = await ScenarioDriver.run(scenario(notes, pieces)).writes.joined()
                if bad.contains(where: written.contains) || written.contains(":.") {
                    return "cut \(cut) of \(sentence.debugDescription) wrote \(written.debugDescription)"
                }
            }
        }
        return nil
    }
}

@Suite("Golden scenarios: the owner's requirements, said and written")
struct GoldenScenarioTests {
    @Test("each scenario writes what the requirement says", arguments: GoldenScenarios.rows)
    func rowWritesWhatIsRequired(_ row: GoldenRow) async {
        if let issue = row.knownIssue {
            await withKnownIssue("\(issue): \(row.id) fails until the issue lands") {
                let failure = await row.check()
                #expect(failure == nil, Comment(rawValue: failure ?? ""))
            }
        } else {
            let failure = await row.check()
            #expect(failure == nil, Comment(rawValue: "\(row.id) \(failure ?? "")"))
        }
    }
}

@Suite("Golden scenarios: the table and the tests agree")
struct GoldenScenarioDocTests {
    private static func documentedIDs() throws -> [String] {
        let page = URL(filePath: #filePath).deletingLastPathComponent().appending(
            path: "../../Docs/golden-scenarios.md")
        let text = try String(contentsOf: page.standardized, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("| G"), let id = line.dropFirst(2).split(separator: " ").first
            else { return nil }
            return String(id)
        }
    }

    @Test("every row of the table has a test or a stated reason, and every test has a row")
    func tableAndTestsAgree() throws {
        let documented = try Self.documentedIDs()
        let built = GoldenScenarios.rows.map(\.id)
        let deferred = Array(GoldenScenarios.deferred.keys)

        #expect(documented.count == 37)
        #expect(Set(documented).count == documented.count)
        #expect(Set(built).count == built.count)
        #expect(Set(documented) == Set(built).union(deferred))
        #expect(Set(built).isDisjoint(with: deferred))
        #expect(GoldenScenarios.deferred.values.allSatisfy { !$0.isEmpty })
    }

    @Test("a known issue names an issue number")
    func knownIssuesAreNamed() {
        for row in GoldenScenarios.rows {
            if let issue = row.knownIssue { #expect(issue.hasPrefix("#") && Int(issue.dropFirst()) != nil) }
        }
    }
}
