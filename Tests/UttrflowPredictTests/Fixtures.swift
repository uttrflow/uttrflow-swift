import Foundation

@testable import UttrflowPredict

/// The one instant every suite measures from, so a decay or a lifetime is exact rather than nearly right.
let moment = Date(timeIntervalSince1970: 1_800_000_000)

/// An instant this many days before ``moment``.
func daysAgo(_ days: Double) -> Date {
    moment.addingTimeInterval(-days * 86_400)
}

/// A terminal sitting in a working directory, which is the only surface the environment answers for.
let terminal = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "/repo")

/// A candidate the corpus has seen, so each test names only what it is about.
func remembered(
    _ text: String = "git commit -m",
    count: Int = 4,
    accepted: Int = 0,
    rejected: Int = 0,
    selfSourced: Int = 0,
    lastUsed: Date = moment,
    editDistance: Int = 0,
    irreversible: Bool = false
) -> Candidate {
    Candidate(
        text: text,
        source: .personal,
        evidence: Entry(
            text: text, count: count, accepted: accepted, rejected: rejected,
            selfSourced: selfSourced, lastUsed: lastUsed),
        editDistance: editDistance,
        isIrreversible: irreversible)
}
