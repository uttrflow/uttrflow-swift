import Foundation
import Testing
import UttrflowPredict
import UttrflowPredictStore

@testable import UttrflowPredictCapture

/// A field in a terminal the person has opted into.
private let shell = FieldReading(bundleIdentifier: "com.example.terminal", role: "AXTextArea")

/// A moment every step is timed from.
private let accepted = Date(timeIntervalSince1970: 1_800_000_000)

/// A session writing to a real corpus, so the counts an undo leaves can be read back.
private func opened(_ scratch: borrowing Scratch) async throws -> (CaptureSession, PredictStore) {
    let store = try PredictStore(path: scratch.path("predict.sqlite"))
    let session = CaptureSession(
        sink: store, preferencesFile: CapturePreferencesFile(path: scratch.preferencesPath))
    try await session.record(.allowed, for: "com.example.terminal")
    return (session, store)
}

/// The evidence the corpus holds for one line in the shell, or nothing once the line is gone.
private func evidence(of text: String, in store: PredictStore) async throws -> Entry? {
    let surface = try #require(shell.surface)
    return try await store.candidates(for: surface, matching: text).first { $0.text == text }?.evidence
}

@Suite("An acceptance undone straight away is taken back")
struct AcceptanceUndoTests {
    @Test(
        "Undo back to what was typed, or backspacing into the acceptance, leaves no new line and no acceptance."
    )
    func undoneAcceptanceLeavesNothing() async throws {
        for undone in ["git s", "git status --sh", ""] {
            let scratch = Scratch()
            let (session, store) = try await opened(scratch)
            _ = try await session.handle(.keystroke("git s", at: accepted), in: shell)
            _ = try await session.accepted("git status --short", in: shell, at: accepted)
            #expect(try await evidence(of: "git status --short", in: store)?.accepted == 1)
            _ = try await session.handle(.keystroke(undone, at: accepted + 1), in: shell)
            #expect(try await evidence(of: "git status --short", in: store) == nil, "undone to \(undone)")
        }
    }

    @Test(
        "An undo of a fuzzy acceptance, back to the typo it corrected, leaves no new line and no acceptance.")
    func undoneFuzzyAcceptanceLeavesNothing() async throws {
        for undone in ["gti st", "gti s"] {
            let scratch = Scratch()
            let (session, store) = try await opened(scratch)
            _ = try await session.handle(.keystroke("gti st", at: accepted), in: shell)
            _ = try await session.accepted("git status --short", over: "gti st", in: shell, at: accepted)
            _ = try await session.handle(.keystroke(undone, at: accepted + 1), in: shell)
            #expect(try await evidence(of: "git status --short", in: store) == nil, "undone to \(undone)")
        }
    }

    @Test("A fuzzy acceptance typed on from, or edited to other text, stands.")
    func fuzzyAcceptanceTypedOnStands() async throws {
        for ending in ["git status --short -b", "git stash"] {
            let scratch = Scratch()
            let (session, store) = try await opened(scratch)
            _ = try await session.accepted("git status --short", over: "gti st", in: shell, at: accepted)
            _ = try await session.handle(.keystroke(ending, at: accepted + 1), in: shell)
            #expect(try await evidence(of: "git status --short", in: store)?.accepted == 1, "\(ending)")
        }
    }

    @Test("An undo of a line typed before keeps its own uses and takes back only the acceptance.")
    func undoKeepsEarlierUses() async throws {
        let scratch = Scratch()
        let (session, store) = try await opened(scratch)
        let surface = try #require(shell.surface)
        for _ in 0..<2 { try await store.record("git status --short", in: surface, at: accepted - 60) }
        _ = try await session.accepted("git status --short", in: shell, at: accepted)
        _ = try await session.handle(.keystroke("git s", at: accepted + 1), in: shell)
        let left = try #require(try await evidence(of: "git status --short", in: store))
        #expect(left.count == 2)
        #expect(left.accepted == 0)
        #expect(left.selfSourced == 0)
    }

    @Test("An acceptance kept, run, typed on from or left alone past the window stands.")
    func keptAcceptanceStands() async throws {
        let endings: [CaptureEvent] = [
            .keystroke("git status --short -b", at: accepted + 1), .returnPressed(at: accepted + 1),
            .keystroke("git s", at: accepted + CaptureSession.undoWindow + 1),
        ]
        for ending in endings {
            let scratch = Scratch()
            let (session, store) = try await opened(scratch)
            _ = try await session.accepted("git status --short", in: shell, at: accepted)
            _ = try await session.handle(ending, in: shell)
            _ = try await session.handle(.keystroke("", at: accepted + 2), in: shell)
            #expect(try await evidence(of: "git status --short", in: store)?.accepted == 1, "\(ending)")
        }
    }

    @Test("An accepted line edited before Return records the final line without an acceptance count.")
    func editedAcceptanceLearnsTheCommittedLine() async throws {
        let scratch = Scratch()
        let (session, store) = try await opened(scratch)
        let prefix = "I will send the report "
        let acceptedText = prefix + "tomorrow."
        let finalText = prefix + "today."
        let surface = try #require(shell.surface)
        try await store.record(acceptedText, in: surface, at: accepted - 60)

        _ = try await session.handle(.keystroke(prefix, at: accepted), in: shell)
        _ = try await session.accepted(acceptedText, over: prefix, in: shell, at: accepted)
        #expect(try await evidence(of: acceptedText, in: store)?.accepted == 1)

        _ = try await session.handle(.typed("today.", at: accepted + 1), in: shell)
        _ = try await session.handle(.keystroke(finalText, at: accepted + 1), in: shell)
        let outcome = try await session.handle(.returnPressed(at: accepted + 2), in: shell)

        #expect(outcome == .recorded(finalText))
        let original = try #require(try await evidence(of: acceptedText, in: store))
        #expect(original.count == 1)
        #expect(original.accepted == 0)
        #expect(original.selfSourced == 0)
        let final = try #require(try await evidence(of: finalText, in: store))
        #expect(final.count == 1)
        #expect(final.accepted == 0)
        #expect(final.selfSourced == 0)
    }
}
