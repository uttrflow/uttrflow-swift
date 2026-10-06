import Foundation
import UttrflowCore

/// The predict log's lines, which carry lengths, counts and reasons and never the text itself. See `Docs/logging.md`.
enum SuggestionLog {
    /// Whether a local debug run opts into application identities in suggestion logs.
    static var revealsApplications: Bool {
        ProcessInfo.processInfo.environment["UTTRFLOW_DEBUG_SUGGESTION_APPLICATIONS"] == "1"
    }

    /// Hides an application's identity unless local debugging explicitly opts in.
    static func application(_ identity: String, reveal: Bool = revealsApplications) -> String {
        reveal ? identity : "private"
    }

    /// What the corpus held for the line.
    static func query(typed: String, corpus: Int, generatorReady: Bool) -> String {
        "QUERY typedChars=\(typed.count) corpus=\(corpus) generatorReady=\(generatorReady)"
    }

    /// The machine knows no word that could come next.
    static func optionsNone(typed: String) -> String {
        "OPTIONS typedChars=\(typed.count) none"
    }

    /// The machine knows which words could come next, and how many.
    static func optionsAmong(typed: String, among: Int) -> String {
        "OPTIONS typedChars=\(typed.count) among=\(among)"
    }

    /// Why nothing is drawn for the focused field's current line.
    static func quiet(
        typed: String, reason: String, rejections: Int, silencedHere: Bool, enabled: Bool
    ) -> String {
        "QUIET typedChars=\(typed.count) reason=\(reason) rejections=\(rejections) silencedHere=\(silencedHere) enabled=\(enabled)"
    }

    /// A model pass that threw, named by its error's type and case.
    static func generateFailed(typed: String, error: any Error) -> String {
        "GENERATE failed typedChars=\(typed.count) error=\(failure(error))"
    }

    /// What the model offered, and how long it took.
    static func generate(
        application: String, typed: String, got: Int, elapsedMilliseconds: Int, firstCompletion: String?,
        revealApplication: Bool = revealsApplications
    ) -> String {
        "GENERATE app=\(self.application(application, reveal: revealApplication)) typedChars=\(typed.count) got=\(got) elapsed=\(elapsedMilliseconds)ms firstChars=\(firstCompletion?.count ?? 0)"
    }

    /// A pass for the list behind the drawn line that threw.
    static func alternativesFailed(typed: String, error: any Error) -> String {
        "ALTERNATIVES failed typedChars=\(typed.count) error=\(failure(error))"
    }

    /// The list behind the drawn line.
    static func alternatives(typed: String, got: Int, elapsedMilliseconds: Int) -> String {
        "ALTERNATIVES typedChars=\(typed.count) got=\(got) elapsed=\(elapsedMilliseconds)ms"
    }

    /// How many of the model's lines the machine denied.
    static func attest(typed: String, offered: Int, standing: Int) -> String {
        "ATTEST typedChars=\(typed.count) in=\(offered) out=\(standing) dropped=\(offered - standing)"
    }

    /// How many remembered lines survived the gates.
    static func verify(
        typed: String, offered: Int, allowed: Int, elapsedMilliseconds: Int, firstCompletion: String?
    ) -> String {
        "VERIFY typedChars=\(typed.count) in=\(offered) out=\(allowed) elapsed=\(elapsedMilliseconds)ms firstChars=\(firstCompletion?.count ?? 0)"
    }

    /// A completion put into the field, and the route that took it.
    static func accept(text: String, typed: String, via route: String) -> String {
        "ACCEPT chars=\(text.count) typedChars=\(typed.count) via=\(route)"
    }

    /// Every route refused the completion; the insertion error's cases carry fixed wording only.
    static func landedNowhere(_ error: TextInsertionError, typed: String) -> String {
        "a completion landed nowhere: \(String(describing: error)) typedChars=\(typed.count)"
    }

    /// The field was not the drawn line at acceptance, so nothing was written; the reason is fixed wording only.
    static func refusedUnwritten(_ reason: String, typed: String) -> String {
        "a completion was refused unwritten: \(reason) typedChars=\(typed.count)"
    }

    /// A turn left behind, named by its step and application identity only when debugging opts in.
    static func stall(
        step: SuggestionTurnStep?, application: String?, afterSeconds seconds: Double,
        revealApplication: Bool = revealsApplications
    ) -> String {
        "STALL step=\(step?.rawValue ?? "unknown") app=\(self.application(application ?? "unknown", reveal: revealApplication)) after=\(Int(seconds))s left behind"
    }

    /// An error's type and case, without the payload, which may hold the text a model was given or wrote.
    static func failure(_ error: any Error) -> String {
        ErrorLog.failure(error)
    }
}

/// The step a suggestion turn is waiting on, which is what a stall log names.
enum SuggestionTurnStep: String, Sendable {
    /// Reading the focused field of the application in front.
    case read
    /// Handing the line to capture.
    case remember
    /// Recording a declined suggestion in the store.
    case reject
    /// Asking the corpus and the machine for candidates.
    case corpus
    /// Putting remembered candidates through the gates.
    case verify
    /// Asking the machine which words may come next.
    case options
    /// Waiting on a model pass for the line.
    case generate
    /// Checking the model's lines against the machine.
    case attest
    /// Scoring the model's lines for the confidence floor.
    case score
    /// Reading the field again before drawing.
    case redraw
    /// Waiting on a model pass for the list behind the drawn line.
    case alternatives
}
