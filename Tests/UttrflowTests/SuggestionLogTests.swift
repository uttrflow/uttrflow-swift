// Tests that the predict log's lines carry sizes and reasons and none of the text they describe.

import Foundation
import Testing
import UttrflowCore

@testable import Uttrflow

/// Every line the coordinator logs, built from invented text that must not appear in it.
@Suite("What the predict log carries")
struct SuggestionLogTests {
    /// An invented line a person might be typing, whose words are each distinctive enough to find.
    private static let typed = "zephyr quokka marmalade"
    /// An invented completion of it.
    private static let offered = "zephyr quokka marmalade trombone"
    /// A distinctive application name and bundle identifier for privacy assertions.
    private static let appName = "Private Editor"
    private static let appBundle = "com.example.private-editor"

    /// Whether any of the invented words reached the line.
    private static func leaks(_ line: String) -> Bool {
        (typed + " " + offered).split(separator: " ").contains { line.contains($0) }
    }

    /// Each builder the coordinator calls, labelled for the failure message.
    private static let lines: [(String, String)] = [
        ("query", SuggestionLog.query(typed: typed, corpus: 2, generatorReady: true)),
        ("optionsNone", SuggestionLog.optionsNone(typed: typed)),
        ("optionsAmong", SuggestionLog.optionsAmong(typed: typed, among: 3)),
        (
            "quiet",
            SuggestionLog.quiet(
                typed: typed, reason: "writingFluently", rejections: 0, silencedHere: false, enabled: true)
        ),
        ("generateFailed", SuggestionLog.generateFailed(typed: typed, error: InventedFailure.wrote(offered))),
        (
            "generate",
            SuggestionLog.generate(
                application: appName, typed: typed, got: 1, elapsedMilliseconds: 40,
                firstCompletion: offered, revealApplication: false)
        ),
        (
            "alternativesFailed",
            SuggestionLog.alternativesFailed(typed: typed, error: InventedFailure.wrote(offered))
        ),
        ("alternatives", SuggestionLog.alternatives(typed: typed, got: 2, elapsedMilliseconds: 90)),
        ("attest", SuggestionLog.attest(typed: typed, offered: 3, standing: 1)),
        (
            "verify",
            SuggestionLog.verify(
                typed: typed, offered: 4, allowed: 1, elapsedMilliseconds: 2, firstCompletion: offered)
        ),
        ("accept", SuggestionLog.accept(text: offered, typed: typed, via: "accessibility")),
        (
            "landedNowhere",
            SuggestionLog.landedNowhere(.insertionRejected(description: offered), typed: typed)
        ),
        (
            "deliveryUnconfirmed",
            SuggestionLog.deliveryUnconfirmed(.insertionInterrupted(typed: 2, total: 4), typed: typed)
        ),
        (
            "refusedUnwritten",
            SuggestionLog.refusedUnwritten("the focused field cannot be read", typed: typed)
        ),
    ]

    @Test("no line carries the typed text or the offered text")
    func noLineCarriesTheText() {
        for (name, line) in Self.lines {
            #expect(!Self.leaks(line), "\(name) logged: \(line)")
        }
    }

    @Test("each line keeps its size, so a run can still be followed")
    func eachLineKeepsItsSize() {
        for (name, line) in Self.lines {
            #expect(line.contains("typedChars=\(Self.typed.count)"), "\(name) logged: \(line)")
        }
        #expect(Self.lines.first { $0.0 == "accept" }?.1.contains("chars=\(Self.offered.count) ") == true)
        #expect(Self.lines.first { $0.0 == "attest" }?.1.contains("dropped=2") == true)
        #expect(
            Self.lines.first { $0.0 == "deliveryUnconfirmed" }?.1.hasPrefix(
                "completion delivery is unconfirmed: TextInsertionError.insertionInterrupted") == true)
    }

    @Test("a stall hides application identity unless debugging requests it")
    func aStallHidesItsApplicationByDefault() {
        let line = SuggestionLog.stall(
            step: .generate, application: Self.appBundle, afterSeconds: 10, revealApplication: false)
        #expect(line == "STALL step=generate app=private after=10s left behind")
        let unknown = SuggestionLog.stall(
            step: nil, application: nil, afterSeconds: 10, revealApplication: false)
        #expect(unknown == "STALL step=unknown app=private after=10s left behind")
    }

    @Test("application identity is hidden unless the debug switch is enabled")
    func applicationIdentityIsPrivateByDefault() {
        let generate = SuggestionLog.generate(
            application: Self.appName, typed: Self.typed, got: 1, elapsedMilliseconds: 1,
            firstCompletion: nil, revealApplication: false)
        let stall = SuggestionLog.stall(
            step: .read, application: Self.appBundle, afterSeconds: 1, revealApplication: false)
        let fieldRead = "FIELD_READ front=\(SuggestionLog.application(Self.appBundle, reveal: false))"
        let turn = "TURN front=\(SuggestionLog.application(Self.appBundle, reveal: false))"
        let off = "OFF app=\(SuggestionLog.application(Self.appBundle, reveal: false))"
        for line in [generate, stall, fieldRead, turn, off] {
            #expect(!line.contains(Self.appName), "\(line)")
            #expect(!line.contains(Self.appBundle), "\(line)")
            #expect(line.contains("private"), "\(line)")
        }
        #expect(SuggestionLog.application(Self.appName, reveal: true) == Self.appName)
    }

    @Test("an error is named by its type and case, and its payload is left out")
    func anErrorKeepsItsCaseAndDropsItsPayload() {
        let named = SuggestionLog.failure(InventedFailure.wrote(Self.offered))
        #expect(named == "InventedFailure.wrote")
        #expect(SuggestionLog.failure(InventedFailure.timedOut) == "InventedFailure.timedOut")
        let bridged = NSError(
            domain: "InventedDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: Self.offered])
        #expect(SuggestionLog.failure(bridged) == "NSError domain=InventedDomain code=7")
        #expect(!Self.leaks(SuggestionLog.failure(InventedStructFailure(detail: Self.offered))))
    }
}

/// An error whose payload holds the text a model wrote, as a real generator's might.
private enum InventedFailure: Error {
    case wrote(String)
    case timedOut
}

/// A struct error whose description would carry its text.
private struct InventedStructFailure: Error {
    let detail: String
}
