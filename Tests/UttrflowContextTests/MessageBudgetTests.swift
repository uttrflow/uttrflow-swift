import Foundation
import Testing

@testable import UttrflowContext

/// Holds each recorded fixture's dictation read to its budget of messages and simulated time.
struct MessageBudgetTests {
    private struct Budget: Codable, Equatable {
        let messages: Int
        let milliseconds: Double
    }

    private static let fixtures = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures")
    private static let directory = fixtures.appending(path: "AccessibilitySnapshots")

    /// Replays a fixture's read at its recorded caret and returns what it cost.
    private static func cost(of file: URL) throws -> Budget {
        let snapshot = try AccessibilitySnapshot.decode(Data(contentsOf: file))
        let tree = ReplayTree(snapshot: snapshot)
        let caret = snapshot.focused.attributes["AXSelectedTextRange"]?.text.flatMap(NSRange.init)
        let names = FocusedFieldRead.names(of: snapshot.focused, in: tree)
        _ = FocusedFieldRead.text(of: snapshot.focused, in: tree, names: names, at: caret)
        let milliseconds = (tree.messages.milliseconds * 10).rounded() / 10
        return Budget(messages: tree.messages.asked.count, milliseconds: milliseconds)
    }

    private static func recorded() throws -> [String: Budget] {
        let data = try Data(contentsOf: fixtures.appending(path: "AccessibilityMessageBudget.json"))
        return try JSONDecoder().decode([String: Budget].self, from: data)
    }

    private static func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test func noFixtureReadSendsMoreMessagesOrTakesLongerThanItsBudget() throws {
        let budgets = try Self.recorded()
        var over: [String] = []
        for file in try Self.files() {
            let name = file.lastPathComponent
            let cost = try Self.cost(of: file)
            guard let budget = budgets[name] else {
                over.append("\(name): no budget; record \(cost.messages) messages, \(cost.milliseconds) ms")
                continue
            }
            if cost.messages > budget.messages || cost.milliseconds > budget.milliseconds {
                over.append("\(name): \(cost.messages) messages, \(cost.milliseconds) ms over \(budget)")
            }
        }
        #expect(over.isEmpty, "\(over.joined(separator: "\n"))")
    }

    /// The budget follows a cheaper read down, so a saving cannot be spent again later.
    @Test func everyBudgetIsTheCostOfItsFixtureAndNamesOneThatExists() throws {
        let budgets = try Self.recorded()
        let files = try Self.files()
        let stale = Set(budgets.keys).subtracting(files.map(\.lastPathComponent))
        #expect(stale.isEmpty, "budgets for missing fixtures: \(stale.sorted())")
        var slack: [String] = []
        for file in files {
            guard let budget = budgets[file.lastPathComponent] else { continue }
            let cost = try Self.cost(of: file)
            if cost != budget {
                slack.append("\(file.lastPathComponent): lower the budget \(budget) to \(cost)")
            }
        }
        #expect(slack.isEmpty, "\(slack.joined(separator: "\n"))")
    }
}
