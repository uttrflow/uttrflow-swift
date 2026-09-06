import Foundation
import UttrflowPredict

/// The substitute machine a fixture stands on: it says what the model may write, and whether what it wrote is there. See `Docs/predict-agent.md`, A5.
struct Grounding {
    /// A machine that answers what the fixture says and nothing else, as the real reader answers for a directory.
    private struct FixtureMachine: EnvironmentReading {
        let answers: [EnvironmentKind: [String]]

        func values(of kind: EnvironmentKind, in directory: String) async -> [String]? { answers[kind] }
    }

    private let verifier: Verifier
    private let surface: Surface
    private let now = Date()

    /// The grounding for a fixture with a machine, warmed so every answer is already in; nothing for a fixture without one.
    init?(for fixture: Fixture) async {
        guard let machine = fixture.machine, let directory = fixture.situation.document else { return nil }
        let index = EnvironmentIndex(reader: FixtureMachine(answers: machine))
        for kind in machine.keys { _ = await index.values(of: kind, in: directory, now: now) }
        await index.settle()
        verifier = Verifier(index: index)
        surface = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: directory)
    }

    /// What the next word may be, as the app would ask before a pass.
    func options(for typed: String) async -> ArgumentOptions {
        await verifier.options(for: typed, in: surface, now: now)
    }

    /// The model's lines the machine lets stand, as the app would sieve them before drawing.
    func standing(_ lines: [String], after typed: String) async -> [String] {
        await verifier.standing(lines, after: typed, in: surface, now: now)
    }
}
