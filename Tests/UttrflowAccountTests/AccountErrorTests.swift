// Tests for AccountError: the catalogue checks UttrflowCore cannot make on a module above it.

import UttrflowCore
import Testing

@testable import UttrflowAccount

/// The cases ``FailureCatalogue`` would walk if Core could see this module; checked here instead.
private let allAccountFailures = AccountError.everyCase

/// Every account failure's message, recovery and severity.
@Suite("What can go wrong signing in")
struct AccountErrorTests {
    @Test("chains every case exactly once")
    func chain() {
        #expect(allAccountFailures.count == 4)
        let described = allAccountFailures.map { "\($0)" }
        #expect(Set(described).count == described.count, "a case is chained twice: \(described)")
    }

    @Test("gives every failure a complete, non-empty sentence")
    func everyFailureExplainsItself() {
        for failure in allAccountFailures {
            #expect(!failure.userMessage.isEmpty, "\(failure) has no message")
            #expect(
                failure.userMessage.hasSuffix(".") || failure.userMessage.hasSuffix("!"),
                "\(failure) message is not a sentence: \(failure.userMessage)")
        }
    }

    /// §16: "OAuth", "token" and "signature" are as meaningless to somebody dictating as "CoreML" is.
    @Test("never leaks implementation vocabulary into a user-facing message")
    func neverNamesAnImplementation() {
        let forbidden = [
            "oauth", "token", "jwt", "signature", "endpoint", "http", "api", "server",
            "whisper", "llm", "inference",
        ]
        for failure in allAccountFailures {
            let message = failure.userMessage.lowercased()
            for term in forbidden {
                #expect(
                    !message.contains(term), "\(failure) leaks '\(term)': \(failure.userMessage)")
            }
        }
    }

    /// The first sign-in is the one occasion a network is genuinely required, so the message says so.
    @Test("says plainly that the first sign-in is the one that needs a connection")
    func firstSignInSaysItNeedsANetwork() {
        let message = AccountError.serverUnreachable.userMessage
        #expect(message.lowercased().contains("internet connection"))
        #expect(message.lowercased().contains("first time"))
    }

    @Test("offers a recovery wherever one could actually help")
    func recoveryActions() {
        // A connection may well have appeared since.
        #expect(AccountError.serverUnreachable.recovery == .retry)
        // Another attempt, or another provider — the user has a real choice.
        #expect(AccountError.providerRefused(description: "x").recovery == .retry)
        // Nothing offered: no number of attempts by the user changes which key this build carries.
        #expect(AccountError.sessionMalformed.recovery == nil)
    }

    /// Every one leaves the Mac with no session, and dictation needs one.
    @Test("treats every sign-in failure as blocking")
    func severities() {
        for failure in allAccountFailures {
            #expect(failure.severity == .blocking, "\(failure) is not blocking")
        }
    }

    /// An expired entitlement is an offline Mac's ordinary state; erroring on it is a step towards a lock.
    @Test("has no failure for an expired entitlement, because that is not a failure")
    func expiryIsNotAFailure() {
        for failure in allAccountFailures {
            let message = failure.userMessage.lowercased()
            for term in ["expire", "lapsed", "out of date", "renew"] {
                #expect(
                    !message.contains(term),
                    "\(failure) treats an aged-out entitlement as something to apologise for")
            }
        }
    }

    @Test("distinguishes failures that carry different detail")
    func equatable() {
        #expect(AccountError.providerRefused(description: "a") != .providerRefused(description: "b"))
        #expect(AccountError.sessionMalformed == .sessionMalformed)
        #expect(AccountError.serverUnreachable != .sessionMalformed)
    }
}
