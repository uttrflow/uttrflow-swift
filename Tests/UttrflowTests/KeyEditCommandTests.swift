// Tests the notice a key press said under the command key ends in, where the destination refuses it.
import Synchronization
import Testing
import UttrflowCore
import UttrflowInput
import UttrflowPipeline
import UttrflowPredict

@testable import Uttrflow

/// Keeps each stroke instead of posting it, so no key reaches the desktop.
private final class RecordingPoster: KeyStrokePosting, Sendable {
    private let strokes = Mutex<[KeyStroke]>([])
    var posted: [KeyStroke] { strokes.withLock { $0 } }
    func post(_ stroke: KeyStroke) throws(TextInsertionError) { strokes.withLock { $0.append(stroke) } }
}

@Suite("A key press under the command key posts its stroke, or the notice says why it posted none")
struct KeyEditCommandTests {
    private let poster = RecordingPoster()
    private var command: KeyEditCommand { KeyEditCommand(overrides: .none, poster: poster) }

    /// The notice a run of `heard` on `target` ends in, as the pipeline builds it from the thrown error.
    private func notice(_ heard: String, on target: AppContext) async -> DictationFailure? {
        do {
            _ = try await command.run(heard, on: target)
            return nil
        } catch {
            return DictationFailure(error, transcript: heard)
        }
    }

    /// The reason `KeyCommand` plans for `heard` on `target`, or nil when it would post.
    private func plannedReason(_ heard: String, on target: AppContext) throws -> String? {
        let row = try #require(KeyCommand.row(heard: heard))
        let destination = DestinationClassifier.classify(target)
        guard case .refused(let reason) = KeyCommand.plan(row, in: destination, isSecure: target.isSecure)
        else { return nil }
        return reason
    }

    @Test(
        "a terminal or a secure field posts nothing, and the notice is the reason with no paste offered",
        arguments: [
            ("press enter", AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")),
            (
                "go to the end",
                AppContext(applicationName: "Notes", bundleIdentifier: "com.apple.Notes", isSecure: true)
            ),
        ])
    func refusalIsTheNotice(heard: String, target: AppContext) async throws {
        let reason = try #require(try plannedReason(heard, on: target))
        let failure = try #require(await notice(heard, on: target))
        #expect(failure.message == reason)
        #expect(failure.recovery == nil)
        #expect(failure.severity == .informational)
        #expect(poster.posted.isEmpty)
    }

    @Test("where the key is on, its stroke is posted and the run says so")
    func postsWhereOn() async throws {
        let mail = AppContext(applicationName: "Mail", bundleIdentifier: "com.apple.mail")
        #expect(try plannedReason("press enter", on: mail) == nil)
        #expect(try await command.run("Press enter.", on: mail) == "Pressed the key.")
        #expect(poster.posted == [KeyStroke(.return)])
    }
}
