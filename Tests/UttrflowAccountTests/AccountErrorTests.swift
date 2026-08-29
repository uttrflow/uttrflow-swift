import UttrflowCore
import Testing

@testable import UttrflowAccount

/// What ``FailureCatalogue`` would walk if it could see this module.
///
/// It cannot — ``UttrflowCore`` owns the catalogue and nothing may depend upwards on the
/// module that owns these three — so the same checks are made here instead. When
/// ``AccountError`` moves down into Core, this list becomes one line in the catalogue
/// and these tests become redundant with the ones in `UttrflowCoreTests`.
private let allAccountFailures = AccountError.everyCase

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

    /// §16: the user must never learn which engine is running, and must never be shown
    /// the vocabulary of the thing that failed either. "OAuth", "token" and "signature"
    /// are as meaningless to somebody trying to dictate as "CoreML" is.
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

    /// The first sign-in is the one occasion a network is genuinely required, so its
    /// message says so plainly rather than hedging about connectivity in general.
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
        // Nothing offered: no number of attempts by the user changes which key was
        // compiled into this build.
        #expect(AccountError.sessionMalformed.recovery == nil)
    }

    /// Every one of them leaves the Mac with no session at all, and dictation needs
    /// one. The severities that vary in this product are the ones where the words still
    /// arrived, and none of these is that.
    @Test("treats every sign-in failure as blocking")
    func severities() {
        for failure in allAccountFailures {
            #expect(failure.severity == .blocking, "\(failure) is not blocking")
        }
    }

    /// The case that must never exist. An expired entitlement is the ordinary state of
    /// a Mac that has been offline for a while, and giving it an error is the first
    /// step towards giving it a lock.
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
