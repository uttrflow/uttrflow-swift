import Foundation
import Testing

@testable import UttrflowAccount

@Suite("Proof Key for Code Exchange")
struct PKCETests {
    /// The digest, computed by something other than the code under test.
    ///
    /// The challenge covers the *verifier string*, not the bytes it was encoded from —
    /// a distinction RFC 7636 §4.2 makes and an implementation can easily get wrong, since
    /// both produce a plausible-looking 43-character value and only one of them is what a
    /// server will compute. This expectation was worked out with `hashlib`, away from the
    /// code it checks.
    @Test("derives the challenge as the base64url SHA-256 of the verifier")
    func challengeIsTheDigest() {
        let pair = PKCEPair(randomBytes: Data(repeating: 0, count: 32))

        #expect(pair.verifier == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        #expect(pair.challenge.count == 43)
        #expect(pair.challenge == "DwBzhbb51LfusnSGBa_hqYSgo7-j8BTQnip4TOnlzRo")
    }

    /// RFC 7636 §4.1: 43 to 128 characters from the unreserved set. A verifier outside it
    /// is refused by a correct server, and the failure would arrive at the token endpoint
    /// rather than here.
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

    /// Padding is not in the unreserved set, so it would have to be percent-encoded in a
    /// query string — where a server comparing raw strings would then never match.
    @Test("never emits padding or the characters base64url replaces")
    func encodingIsURLSafe() {
        // 0xFB 0xFF encodes to `+/` in standard base64, which is exactly what must not
        // appear here.
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

    /// Anything that is not the answer we are waiting for is nothing. A browser will send
    /// a favicon request to this port within milliseconds of opening the page, and treating
    /// that as a callback would end the sign-in with no code.
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

    /// The page is the last thing the person sees of the sign-in, so it must say the right
    /// thing in both directions and carry nothing that could leak.
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
