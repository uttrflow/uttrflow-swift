// Tests for PKCEPair, the loopback listener's request parsing and reply page, and who it listens to.

import Foundation
import Network
import Synchronization
import Testing

@testable import UttrflowAccount

/// The verifier and challenge pair, checked against RFC 7636.
@Suite("Proof Key for Code Exchange")
struct PKCETests {
    /// The challenge covers the verifier string, not its bytes (RFC 7636 §4.2); the digest is from `hashlib`.
    @Test("derives the challenge as the base64url SHA-256 of the verifier")
    func challengeIsTheDigest() {
        let pair = PKCEPair(randomBytes: Data(repeating: 0, count: 32))

        #expect(pair.verifier == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        #expect(pair.challenge.count == 43)
        #expect(pair.challenge == "DwBzhbb51LfusnSGBa_hqYSgo7-j8BTQnip4TOnlzRo")
    }

    /// RFC 7636 §4.1: 43 to 128 characters from the unreserved set, or the token endpoint refuses it.
    @Test("produces a verifier the specification permits")
    func verifierIsWellFormed() {
        for size in [32, 48, 64] {
            let pair = PKCEPair(randomBytes: Data(repeating: 0xAB, count: size))
            #expect(pair.verifier.count >= 43 && pair.verifier.count <= 128)
            #expect(
                pair.verifier.range(of: "^[A-Za-z0-9\\-._~]+$", options: .regularExpression) != nil,
                "\(pair.verifier) is outside the unreserved set")
        }
    }

    /// Padding is outside the unreserved set; percent-encoded, it never matches a raw comparison.
    @Test("never emits padding or the characters base64url replaces")
    func encodingIsURLSafe() {
        // 0xFB 0xFF encodes to `+/` in standard base64, which is exactly what must not appear here.
        let pair = PKCEPair(randomBytes: Data(repeating: 0xFB, count: 32))
        for encoded in [pair.verifier, pair.challenge] {
            #expect(!encoded.contains("+"))
            #expect(!encoded.contains("/"))
            #expect(!encoded.contains("="))
        }
    }

    @Test("gives every attempt its own pair")
    func pairsDiffer() {
        let first = PKCEPair(randomBytes: HTTPAuthenticationService.systemRandomBytes(32))
        let second = PKCEPair(randomBytes: HTTPAuthenticationService.systemRandomBytes(32))
        #expect(first.verifier != second.verifier)
        #expect(first.challenge != second.challenge)
    }
}

/// What ``SystemLoopbackListener`` makes of the request the browser sends, and the page it answers with.
@Suite("The browser coming back to the loopback port")
struct LoopbackParsingTests {
    /// The request a browser actually sends, first line and all.
    @Test("reads the code and the state out of the request line")
    func readsACallback() throws {
        let request = """
            GET /callback?code=the-code&state=the-state HTTP/1.1\r
            Host: 127.0.0.1:49152\r
            User-Agent: something\r
            \r

            """
        let callback = try #require(SystemLoopbackListener.parse(request))
        #expect(callback.code == "the-code")
        #expect(callback.state == "the-state")
    }

    @Test("decodes what the browser percent-encoded")
    func decodesEscapes() throws {
        let callback = try #require(
            SystemLoopbackListener.parse("GET /callback?code=a%2Fb&state=c%20d HTTP/1.1\r\n\r\n"))
        #expect(callback.code == "a/b")
        #expect(callback.state == "c d")
    }

    /// A browser requests a favicon within milliseconds; treating that as a callback ends the sign-in.
    @Test("ignores everything that is not a callback")
    func ignoresEverythingElse() {
        for request in [
            "GET /favicon.ico HTTP/1.1\r\n\r\n",
            "GET /callback HTTP/1.1\r\n\r\n",
            "GET /callback?code=only-a-code HTTP/1.1\r\n\r\n",
            "GET /callback?state=only-a-state HTTP/1.1\r\n\r\n",
            "POST /callback?code=c&state=s HTTP/1.1\r\n\r\n",
            "nonsense",
            "",
        ] {
            #expect(SystemLoopbackListener.parse(request) == nil, "accepted: \(request)")
        }
    }

    /// The page is the last thing the person sees, so it says the right thing both ways and leaks nothing.
    @Test("answers the browser with a page carrying no secret")
    func thePageSaysWhatHappened() {
        let signedIn = SystemLoopbackListener.page(signedIn: true)
        #expect(signedIn.contains("Signed in"))
        #expect(signedIn.contains("close this window"))

        let failed = SystemLoopbackListener.page(signedIn: false)
        #expect(failed.contains("Sign-in failed"))

        for page in [signedIn, failed] {
            #expect(!page.contains("code="))
            #expect(!page.contains("<script"))
        }
    }
}

/// The real listener on a real loopback port, driven by raw requests the way a browser or a stranger sends them.
@Suite("Who the loopback port listens to")
struct LoopbackListenerTests {
    /// The state the sign-in under test started with.
    private static let state = "the-state"

    /// Sends one raw request to `port` and returns everything that comes back, or "" when the port hangs up.
    private func get(_ path: String, port: UInt16) async -> String {
        await withCheckedContinuation { continuation in
            let once = Mutex(false)
            let finish: @Sendable (String) -> Void = { text in
                guard
                    once.withLock({ used in
                        defer { used = true }; return !used
                    })
                else { return }
                continuation.resume(returning: text)
            }
            let connection = NWConnection(
                host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any, using: .tcp)
            let collected = Mutex(Data())
            @Sendable func read() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                    data, _, isComplete, error in
                    if let data { collected.withLock { $0.append(data) } }
                    if isComplete || error != nil {
                        connection.cancel()
                        finish(String(decoding: collected.withLock { $0 }, as: UTF8.self))
                    } else {
                        read()
                    }
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
                    connection.send(
                        content: Data(request.utf8), completion: .contentProcessed { _ in read() })
                case .failed, .cancelled:
                    finish(String(decoding: collected.withLock { $0 }, as: UTF8.self))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    /// Binds a listener expecting ``state`` and returns it with its port.
    private func bound() async throws -> (SystemLoopbackListener, UInt16) {
        let listener = SystemLoopbackListener()
        let redirect = try await listener.bind(expecting: Self.state)
        let port = try #require(redirect.port.flatMap { UInt16(exactly: $0) })
        #expect(redirect.host() == "127.0.0.1")
        return (listener, port)
    }

    /// A local process that reaches the port first must not end the sign-in or be told it succeeded.
    @Test("refuses a callback with the wrong state and waits for the right one")
    func aWrongStateDoesNotWin() async throws {
        let (listener, port) = try await bound()

        let forged = await get("/callback?code=forged&state=not-the-state", port: port)
        #expect(forged.hasPrefix("HTTP/1.1 400"))
        #expect(forged.contains("Sign-in failed"))

        let missing = await get("/callback?code=forged", port: port)
        #expect(missing.hasPrefix("HTTP/1.1 400"))

        let real = await get("/callback?code=the-code&state=\(Self.state)", port: port)
        #expect(real.hasPrefix("HTTP/1.1 200"))
        #expect(real.contains("Signed in"))

        let callback = try await listener.awaitCallback()
        #expect(callback == LoopbackCallback(code: "the-code", state: Self.state))
        await listener.close()
    }

    /// The waiter is resumed by the matching callback only, however many wrong ones come first.
    @Test("hands the right callback to a waiter already waiting")
    func aWaiterGetsTheRightCallback() async throws {
        let (listener, port) = try await bound()
        let waiter = Task { try await listener.awaitCallback() }

        _ = await get("/callback?code=forged&state=wrong", port: port)
        _ = await get("/callback?code=the-code&state=\(Self.state)", port: port)

        #expect(try await waiter.value.code == "the-code")
        await listener.close()
    }

    /// Once the attempt has its answer, a second code carrying the same state is not spent or praised.
    @Test("answers only the first matching callback as signed in, and a reload of it")
    func onlyTheFirstMatchingCallbackCounts() async throws {
        let (listener, port) = try await bound()

        let first = await get("/callback?code=the-code&state=\(Self.state)", port: port)
        let reload = await get("/callback?code=the-code&state=\(Self.state)", port: port)
        let second = await get("/callback?code=another&state=\(Self.state)", port: port)

        #expect(first.hasPrefix("HTTP/1.1 200"))
        #expect(reload.hasPrefix("HTTP/1.1 200"))
        #expect(second.hasPrefix("HTTP/1.1 400"))
        #expect(try await listener.awaitCallback().code == "the-code")
        await listener.close()
    }

    /// A process hammering the port cannot make the listener hold connections without end.
    @Test("stops accepting connections past the limit for one attempt")
    func connectionsAreCapped() async throws {
        let (listener, port) = try await bound()

        for _ in 0..<SystemLoopbackListener.connectionLimit {
            let answer = await get("/favicon.ico", port: port)
            #expect(answer.hasPrefix("HTTP/1.1 400"))
        }
        let refused = await get("/callback?code=the-code&state=\(Self.state)", port: port)
        #expect(refused.isEmpty)
        await listener.close()
    }

    /// With no expected state nothing matches, so a listener that was never bound hands nothing on.
    @Test("matches nothing when no state is expected")
    func noExpectedStateMatchesNothing() {
        let callback = LoopbackCallback(code: "c", state: "s")
        #expect(!SystemLoopbackListener.answers(callback, expecting: nil, received: nil))
        #expect(SystemLoopbackListener.answers(callback, expecting: "s", received: nil))
        #expect(SystemLoopbackListener.answers(callback, expecting: "s", received: callback))
        #expect(
            !SystemLoopbackListener.answers(
                callback, expecting: "s", received: LoopbackCallback(code: "other", state: "s")))
    }
}
