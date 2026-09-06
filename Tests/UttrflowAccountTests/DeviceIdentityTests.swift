// Tests for MacDeviceIdentity, the token stores, BackendResponse and Timestamp.

import Foundation
import Testing

@testable import UttrflowAccount

/// The registration this Mac sends, and the install identifier it keeps.
@Suite("What this machine tells the backend about itself")
struct DeviceIdentityTests {
    /// An identity over `storage` that mints `identifier` when it holds none.
    private func identity(
        storage: MemoryStorage, name: String = "Naveen's MacBook Pro",
        appVersion: String? = "0.1.0", minting identifier: String = "install-0123456789"
    ) -> MacDeviceIdentity {
        MacDeviceIdentity(
            storage: storage, name: { name }, appVersion: appVersion,
            makeInstallIdentifier: { identifier })
    }

    @Test("says what it is, what it is called, and which build is talking")
    func describesItself() {
        let registration = identity(storage: MemoryStorage()).registration()

        #expect(registration.installID == "install-0123456789")
        #expect(registration.platform == "macos")
        #expect(registration.name == "Naveen's MacBook Pro")
        #expect(registration.appVersion == "0.1.0")
    }

    /// One installation is one device, or the list that "sign my old laptop out" is built on is useless.
    @Test("mints its identifier once and keeps it")
    func identifierIsStable() {
        let storage = MemoryStorage()
        let first = identity(storage: storage, minting: "first").registration().installID
        let second = identity(storage: storage, minting: "second").registration().installID

        #expect(first == "first")
        #expect(second == "first", "a second reading minted a new identifier")
    }

    @Test("keeps it under a versioned key of its own, not with the profile")
    func versionedKey() {
        let storage = MemoryStorage()
        _ = identity(storage: storage).registration()
        #expect(storage.keys == [MacDeviceIdentity.defaultKey])
        #expect(MacDeviceIdentity.defaultKey.hasSuffix(".v1"))
    }

    /// A lost identifier costs one extra row; refusing to sign in over it would cost the app.
    @Test("mints a new one rather than refusing, when what was stored is not readable")
    func unreadableIdentifiersAreReplaced() {
        for stored in [Data(), Data([0xFF, 0xFE, 0x00])] {
            let storage = MemoryStorage([MacDeviceIdentity.defaultKey: stored])
            #expect(identity(storage: storage, minting: "fresh").registration().installID == "fresh")
        }
    }

    @Test("says nothing about the version rather than guessing when it has none")
    func versionIsOptional() {
        let registration = identity(storage: MemoryStorage(), appVersion: nil).registration()
        #expect(registration.appVersion == nil)
    }

    /// Default `UUID` identifiers must satisfy the backend's `opaque_identifier` domain, or sign-in is a 500.
    @Test("mints identifier-shaped values by default")
    func defaultIdentifiersAreIdentifierShaped() {
        let minted = MacDeviceIdentity(
            storage: MemoryStorage(), name: { "Mac" }, appVersion: nil
        ).registration().installID

        #expect(minted.count >= 8)
        #expect(minted.range(of: "^[A-Za-z0-9][A-Za-z0-9_.:@=+/-]*$", options: .regularExpression) != nil)
    }
}

/// The in-memory token store.
@Suite("Where the credential lives")
struct TokenStoreTests {
    @Test("keeps a refresh token, replaces it, and gives it up on signing out")
    func roundTrip() {
        let tokens = InMemoryTokenStore()
        #expect(tokens.refreshToken() == nil)

        tokens.store("first")
        #expect(tokens.refreshToken() == "first")

        // Rotation: every refresh replaces it, and the replaced one is already dead.
        tokens.store("second")
        #expect(tokens.refreshToken() == "second")

        tokens.clear()
        #expect(tokens.refreshToken() == nil)
    }

    @Test("can be built already holding one, for a test that starts signed in")
    func preloaded() {
        #expect(InMemoryTokenStore(refreshToken: "kept").refreshToken() == "kept")
    }
}

/// ``BackendResponse`` and ``BackendUnreachable``, the value types on the wire.
@Suite("The wire")
struct BackendTransportTests {
    /// A proxy re-cases header names; matching one spelling would re-download the profile for ever.
    @Test("finds a header however the server capitalised it")
    func headersAreCaseInsensitive() {
        let response = BackendResponse(status: 200, headers: ["ETag": "\"v1\"", "x-other": "1"])
        #expect(response.header("etag") == "\"v1\"")
        #expect(response.header("ETAG") == "\"v1\"")
        #expect(response.header("X-Other") == "1")
        #expect(response.header("missing") == nil)
    }

    @Test("counts every 2xx as success and nothing else")
    func success() {
        #expect(BackendResponse(status: 200).isSuccess)
        #expect(BackendResponse(status: 204).isSuccess)
        #expect(BackendResponse(status: 304).isSuccess == false)
        #expect(BackendResponse(status: 401).isSuccess == false)
    }

    @Test("says which URL could not be reached, and why")
    func unreachableDescribesItself() {
        let failure = BackendUnreachable(url: Stub.baseURL, reason: "offline")
        #expect(failure.description.contains("offline"))
        #expect(failure.description.contains(Stub.baseURL.absoluteString))
    }
}

/// ``Timestamp``, and the two date encodings a profile carries.
@Suite("Timestamps on the wire")
struct TimestampTests {
    /// What `toISOString()` writes, which is what the backend sends.
    @Test("reads the milliseconds the backend always sends")
    func withMilliseconds() {
        #expect(
            Timestamp.date(from: "2026-08-27T09:20:41.000Z")
                == Date(timeIntervalSince1970: 1_787_822_441))
    }

    /// "Always" is one backend's habit; a date without milliseconds is no reason to sign anybody out.
    @Test("reads one without them too")
    func withoutMilliseconds() {
        #expect(
            Timestamp.date(from: "2026-08-27T09:20:41Z")
                == Date(timeIntervalSince1970: 1_787_822_441))
    }

    @Test("refuses anything that is not a timestamp")
    func nonsense() {
        for text in ["", "yesterday", "2026-13-45T99:99:99Z", "1787822441"] {
            #expect(Timestamp.date(from: text) == nil, "\(text) was read as a date")
        }
    }

    @Test("writes what it can read")
    func roundTrip() throws {
        let moment = Date(timeIntervalSince1970: 1_787_822_441)
        let written = Timestamp.string(from: moment)
        #expect(written == "2026-08-27T09:20:41.000Z")
        #expect(Timestamp.date(from: written) == moment)
    }

    /// One launch writes the profile and the next reads it, so both date encodings must agree.
    @Test("survives a profile going to disk and coming back")
    func profileRoundTrip() throws {
        let profile = Fixture.profile(for: Fixture.entitlement(expiring: 86_400))
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(Profile.self, from: data) == profile)
    }

    @Test("refuses a document whose timestamps are not ones")
    func malformedDocument() {
        let json = Data(
            #"{"identifier":"d","platform":"macos","name":"Mac","lastSeenAt":"soon","isCurrent":true}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Profile.Device.self, from: json)
        }
    }
}
